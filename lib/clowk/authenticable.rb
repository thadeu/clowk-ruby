# frozen_string_literal: true

require "active_support/concern"
require "digest"

module Clowk
  module Authenticable
    extend ActiveSupport::Concern

    # What a liveness check can raise once Clowk::Http's retries are spent, plus
    # connection-refused, which retries never cover. Anything else is a bug and
    # must not be swallowed into "the session is probably fine".
    BROKER_UNAVAILABLE = [SystemCallError, Timeout::Error, IOError, SocketError, EOFError].freeze

    def self.install_dynamic_methods(base)
      scope = Clowk.config.prefix_by.to_s
      current_method = :"current_#{scope}"
      authenticate_method = :"authenticate_#{scope}!"
      signed_in_method = :"#{scope}_signed_in?"

      enforce_session_method = :"#{scope}_enforce_session!"
      enforce_fresh_method = :"#{scope}_enforce_fresh_session!"
      sign_out_method = :"#{scope}_sign_out!"

      base.class_eval do
        unless current_method == :clowk_current_resource
          define_method(current_method) do
            clowk_current_resource
          end
        end

        unless authenticate_method == :clowk_authenticate!
          define_method(authenticate_method) do
            clowk_authenticate!
          end
        end

        unless signed_in_method == :clowk_signed_in?
          define_method(signed_in_method) do
            clowk_signed_in?
          end
        end

        unless enforce_session_method == :clowk_enforce_session!
          define_method(enforce_session_method) do
            clowk_enforce_session!
          end
        end

        unless enforce_fresh_method == :clowk_enforce_fresh_session!
          define_method(enforce_fresh_method) do
            clowk_enforce_fresh_session!
          end
        end

        unless sign_out_method == :clowk_sign_out!
          define_method(sign_out_method) do
            clowk_sign_out!
          end
        end

        helper_method current_method, authenticate_method, signed_in_method, :current_token if respond_to?(:helper_method)
      end
    end

    included do
      Clowk::Authenticable.install_dynamic_methods(self)
    end

    # Per-request credentials — for apps whose keys are not a boot constant:
    # an operator pastes a publishable key into a settings screen, or one
    # process serves several tenants.
    #
    # There is no method here for that, on purpose. `Clowk.with_credentials`
    # does it, works the same in a job or a rake task, and one name is one name
    # to remember:
    #
    #   around_action :require_tenant_key!
    #
    #   def require_tenant_key!(&)
    #     Clowk.with_credentials(publishable_key: Tenant.current.key, &)
    #   end
    #
    # Name that filter whatever your app calls the idea, and spell the block
    # however you like — `(&)`, `(&block)`, `{ yield }`. Nothing in this gem
    # looks for a method of its own naming, and no macro installs a callback
    # for you. `around_action` has to wrap `authenticate_clowk_user!`, and
    # where it sits among your own filters is a decision only your app can make.

    def clowk_current_resource
      @clowk_current_resource ||= begin
        payload = stored_user_payload || verified_request_payload
        payload ? Current.new(payload) : nil
      end
    end

    def current_token
      stored_session&.dig("token") || extracted_token
    end

    def clowk_signed_in?
      clowk_current_resource.present?
    end

    # @param force [Boolean] ignore any cached status and ask Clowk now
    def clowk_session_status(force: false)
      return @clowk_session_status if defined?(@clowk_session_status) && !force

      @clowk_session_status = resolve_session_status(force: force)
    end

    # @param force [Boolean] see {#clowk_session_status}
    def clowk_session_active?(force: false)
      status = clowk_session_status(force: force)

      # "Could not ask" rather than "not active": a blip on the way to a single
      # droplet must not sign everyone out. max_session_age is the bound on how
      # long that can carry a session Clowk would have refused.
      return true if @clowk_session_check_unavailable && Clowk.config.fail_open_on_broker_error

      status&.dig(:status) == "active"
    end

    # Ends the session unless Clowk says, right now, that it still stands.
    #
    # For the handful of actions where a cached "active" is not good enough:
    # rotating a secret, deleting an account, removing a member. Everything else
    # should take the cached check — this is a round trip, on purpose.
    #
    #   before_action :clowk_enforce_fresh_session!, only: [:destroy]
    #
    # Under a configured prefix_by it is named for the scope, like every other
    # method here: `clowk_user_enforce_fresh_session!`.
    #
    # Before 0.7 the only way to get this was `session_status_ttl = 0`, which
    # bought freshness here by paying a round trip on every page instead.
    def clowk_enforce_fresh_session!
      clowk_enforce_session!(force: true)
    end

    # @param force [Boolean] see {#clowk_session_status}
    def clowk_enforce_session!(force: false)
      # Nothing to enforce against a request that carries no session. Reached
      # through clowk_authenticate! this is already true, but the method is also
      # a before_action in its own right — and called that way with no session it
      # read "not active" and ended one that never existed. On a page that skips
      # the identity gate on purpose (an invite link, a public page that shows
      # more when signed in) that threw away whatever the redirect was carrying.
      return unless clowk_signed_in?

      return clowk_expire_session!(nil) if clowk_session_beyond_max_age?
      return if clowk_session_active?(force: force)

      clowk_expire_session!(clowk_session_status)
    end

    def clowk_authenticate!
      return clowk_handle_unauthenticated unless clowk_signed_in?

      # A valid token proves who signed in, not that the session still stands —
      # revocation lives server-side. Opt in with config.enforce_active_session
      # to pay a lookup (cached for session_status_ttl) on every authentication.
      if Clowk.config.enforce_active_session
        clowk_enforce_session!
        return if respond_to?(:performed?) && performed?
      end

      clowk_current_resource
    end

    def clowk_sign_out!
      clowk_session_store&.delete(Clowk.config.session_key)
      clowk_cookie_jar&.delete(Clowk.config.cookie_key)

      @clowk_current_resource = nil
    end

    private

    # ActionController::API is the reliable signal, and it has to be checked
    # directly. Probing `session` does not work: with no session middleware
    # loaded, `request.session` still returns a Session object that responds to
    # `[]` and reads as nil — writes vanish, but nothing raises. Inferring
    # "there is a session, so this is a browser" from that answered every API
    # call with a 302 to a sign-in page the caller cannot follow.
    def clowk_api_only?
      defined?(ActionController::API) && is_a?(ActionController::API)
    end

    def clowk_api_request?
      clowk_api_only? || clowk_session_store.nil? || request.format.json?
    end

    def clowk_handle_unauthenticated
      if clowk_api_request?
        render json: {error: "Unauthorized"}, status: :unauthorized
      else
        redirect_to clowk_sign_in_path(return_to: request.fullpath)
      end
    end

    # One route out of a session that must end, whatever ended it — the broker
    # said inactive, or the local ceiling passed. Apps hook it with
    # config.on_session_expired; the default answers 401 or redirects.
    def clowk_expire_session!(session_info)
      callback = Clowk.config.on_session_expired

      if callback.respond_to?(:call)
        callback.call(self, session_info)

        return
      end

      clowk_handle_expired_session(session_info)
    end

    # A ceiling Clowk plays no part in. Without it, failing open on an
    # unreachable broker would mean a session that never ends.
    #
    # signed_in_at is stamped once, when the session is established:
    # clowk_current_resource prefers the stored payload, so persist_clowk_session
    # does not run again while the session stands.
    def clowk_session_beyond_max_age?
      max = Clowk.config.max_session_age.to_i

      return false unless max.positive?

      started = (stored_session&.dig("signed_in_at") || stored_session&.dig(:signed_in_at)).to_i

      started.positive? && (Time.now.to_i - started) > max
    end

    def clowk_handle_expired_session(_session_info)
      if clowk_api_request?
        render json: {error: "Session expired or inactive"}, status: :unauthorized
      else
        redirect_to clowk_sign_in_path(return_to: request.fullpath)
      end
    end

    # nil in API-only controllers. Not because `session` raises there — it does
    # not, see clowk_api_only? — but because whatever it hands back writes to
    # nowhere, and callers branch on this to decide whether persisting is worth
    # doing at all.
    def clowk_session_store
      return @clowk_session_store if defined?(@clowk_session_store)

      @clowk_session_store =
        if clowk_api_only?
          nil
        else
          begin
            store = session
            store.respond_to?(:[]) ? store : nil
          rescue
            nil
          end
        end
    end

    def clowk_cookie_jar
      return @clowk_cookie_jar if defined?(@clowk_cookie_jar)

      @clowk_cookie_jar = begin
        jar = cookies
        jar.respond_to?(:[]=) ? jar : nil
      rescue
        nil
      end
    end

    def verified_request_payload
      return unless extracted_token

      payload = Clowk::JwtVerifier.new.verify(extracted_token)
      persist_clowk_session(extracted_token, payload)

      payload
    rescue Clowk::InvalidTokenError
      nil
    end

    # Bearer header or cookie only — never the query string. A valid token in a
    # URL would otherwise sign the visitor in on ANY path, bypassing the state
    # check that makes the OAuth callback safe, and would stay replayable for the
    # token's full lifetime anywhere the URL was logged. CallbacksController
    # reads params directly, after validating state.
    def extracted_token
      @extracted_token ||= Clowk::Middleware::TokenExtractor.new(request, token_param: nil).call
    end

    def stored_session
      store = clowk_session_store
      return if store.nil?

      raw_session = store[Clowk.config.session_key]
      return unless raw_session.respond_to?(:to_h)

      raw_session.to_h
    end

    def stored_user_payload
      payload = stored_session&.dig("user") || stored_session&.dig(:user)
      payload&.deep_symbolize_keys
    end

    # No-op for API-only apps. A bearer request must not come back with a
    # Set-Cookie: there is no browser to hold it, the mobile client ignores it,
    # and writing a session per request defeats the point of being stateless.
    def persist_clowk_session(token, payload)
      store = clowk_session_store
      return if store.nil?

      store[Clowk.config.session_key] = {
        token:,
        user: payload,
        signed_in_at: Time.now.to_i
      }

      clowk_cookie_jar&.[]=(Clowk.config.cookie_key, {
        value: token,
        httponly: true,
        same_site: :lax,
        secure: request.ssl?
      })
    end

    def resolve_session_status(force: false)
      @clowk_session_check_unavailable = false
      cached = force ? nil : clowk_read_cached_session_status

      return cached if cached

      resource = clowk_current_resource

      return unless resource&.session_id
      secret_key = Clowk.credentials.secret_key

      return unless secret_key.present?

      client = Clowk::SDK::Client.new(secret_key: secret_key)
      result = client.tokens.verify_with_session(token: current_token)
      status = result&.dig(:session)

      clowk_write_cached_session_status(status) if status

      status
    rescue Clowk::InvalidTokenError
      nil
    rescue *BROKER_UNAVAILABLE => e
      # Never cached: "we could not ask" is not an answer worth keeping, and the
      # next request should try again rather than inherit this one's bad luck.
      @clowk_session_check_unavailable = true

      Clowk.config.http_logger&.warn("[Clowk] session check unavailable: #{e.class}: #{e.message}")

      nil
    end

    def clowk_read_cached_session_status
      if clowk_session_store
        cached = stored_session&.dig("session_status") || stored_session&.dig(:session_status)

        return cached&.deep_symbolize_keys if cached && clowk_session_status_fresh?

        return nil
      end

      store = clowk_status_cache
      return nil unless store

      store.read(clowk_status_cache_key)&.deep_symbolize_keys
    end

    # A TTL of zero means "never trust a cached status", so there is nothing to
    # write anywhere — the read side already discards whatever is there
    # (clowk_session_status_fresh? is false without a positive TTL).
    #
    # The guard used to sit below the session branch and cover only the external
    # cache, so an app that set the TTL to zero — to guarantee a genuinely fresh
    # check before a destructive action — still had the full status payload
    # written into its session on every single request, and never read back.
    # That is write-only weight in a cookie with 4096 bytes to live in, and it
    # ends as ActionDispatch::Cookies::CookieOverflow on whichever request
    # happens to add a flash message.
    def clowk_write_cached_session_status(status)
      ttl = Clowk.config.session_status_ttl.to_i

      return unless ttl.positive?

      if clowk_session_store
        clowk_session_store[Clowk.config.session_key] = stored_session.merge(
          "session_status" => status,
          "session_status_checked_at" => Time.now.to_i
        )

        return
      end

      store = clowk_status_cache

      return unless store

      store.write(clowk_status_cache_key, status, expires_in: ttl)
    end

    # Stateless apps have no session to hang the cached status on, so without an
    # external store every authenticated request would pay a round trip to
    # Clowk. Keyed by token digest — the raw token must not end up in a cache
    # key that could be logged.
    def clowk_status_cache
      Clowk.config.session_status_cache
    end

    def clowk_status_cache_key
      "clowk:session_status:#{Digest::SHA256.hexdigest(current_token.to_s)}"
    end

    # Whether the cached status may still be trusted. Timestamped alongside the
    # payload rather than inside it, so what we hand back stays exactly what the
    # API returned.
    def clowk_session_status_fresh?
      ttl = Clowk.config.session_status_ttl.to_i
      return false unless ttl.positive?

      checked_at = (stored_session&.dig("session_status_checked_at") ||
                    stored_session&.dig(:session_status_checked_at)).to_i

      checked_at.positive? && (Time.now.to_i - checked_at) < ttl
    end
  end
end
