# frozen_string_literal: true

require "active_support/concern"
require "digest"

module Clowk
  module Authenticable
    extend ActiveSupport::Concern

    def self.install_dynamic_methods(base)
      scope = Clowk.config.prefix_by.to_s
      current_method = :"current_#{scope}"
      authenticate_method = :"authenticate_#{scope}!"
      signed_in_method = :"#{scope}_signed_in?"

      enforce_session_method = :"#{scope}_enforce_session!"
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

    def clowk_session_status
      @clowk_session_status ||= resolve_session_status
    end

    def clowk_session_active?
      clowk_session_status&.dig(:status) == "active"
    end

    def clowk_enforce_session!
      return if clowk_session_active?

      session_info = clowk_session_status
      callback = Clowk.config.on_session_expired

      if callback.respond_to?(:call)
        callback.call(self, session_info)

        return
      end

      clowk_handle_expired_session(session_info)
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

    def resolve_session_status
      cached = clowk_read_cached_session_status

      return cached if cached

      resource = clowk_current_resource

      return unless resource&.session_id
      return unless Clowk.config.secret_key.present?

      client = Clowk::SDK::Client.new(secret_key: Clowk.config.secret_key)
      result = client.tokens.verify_with_session(token: current_token)
      status = result&.dig(:session)

      clowk_write_cached_session_status(status) if status

      status
    rescue Clowk::InvalidTokenError
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

    def clowk_write_cached_session_status(status)
      if clowk_session_store
        clowk_session_store[Clowk.config.session_key] = stored_session.merge(
          "session_status" => status,
          "session_status_checked_at" => Time.now.to_i
        )

        return
      end

      ttl = Clowk.config.session_status_ttl.to_i
      store = clowk_status_cache

      return unless store && ttl.positive?

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
