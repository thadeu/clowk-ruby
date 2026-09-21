# frozen_string_literal: true

module Clowk
  class Configuration
    attr_accessor :api_base_url
    attr_accessor :app_base_url
    attr_accessor :callback_path
    attr_accessor :cookie_key
    attr_accessor :http_logger
    attr_accessor :http_open_timeout
    attr_accessor :http_read_timeout
    attr_accessor :http_retry_attempts
    attr_accessor :http_retry_interval
    attr_accessor :http_write_timeout
    attr_writer :audience
    attr_accessor :issuer
    attr_accessor :jwks_url
    attr_accessor :mount_path
    attr_accessor :publishable_key
    attr_accessor :prefix_by
    attr_accessor :secret_key
    attr_accessor :session_key
    attr_accessor :subdomain_url
    attr_accessor :token_param
    attr_accessor :enforce_active_session
    attr_accessor :on_session_expired
    attr_accessor :session_status_ttl
    attr_accessor :max_session_age
    attr_accessor :fail_open_on_broker_error
    attr_accessor :token_store
    attr_writer :session_status_cache

    def initialize
      @api_base_url = "https://api.clowk.dev/api/v1"
      @app_base_url = "https://app.clowk.in"
      @after_sign_in_path = "/"
      @after_sign_out_path = "/"
      @mount_path = "/clowk"
      @callback_path = "/clowk/oauth/callback"
      @cookie_key = "clowk_token"
      @http_logger = nil
      @http_open_timeout = 5
      @http_read_timeout = 10
      @http_retry_attempts = 2
      @http_retry_interval = 0.05
      @http_write_timeout = 10
      @issuer = "clowk"
      @session_key = :clowk
      @prefix_by = :clowk
      @token_param = :token
      @enforce_active_session = false
      @on_session_expired = nil
      # How long a fetched session status stays trusted, in seconds. Without a
      # TTL the first lookup would be cached for the life of the Rails session,
      # which silently turns every later enforcement call into a no-op. Set 0 to
      # check on every call.
      @session_status_ttl = 300

      # A local ceiling the broker plays no part in, so a permanently
      # unreachable Clowk cannot keep a session alive forever — the other half
      # of failing open. nil leaves the broker as the only authority.
      @max_session_age = nil

      # A network blip must not sign everyone out. When the liveness check
      # cannot be made at all, the session is left standing and checked again on
      # the next request; max_session_age is what bounds that.
      @fail_open_on_broker_error = true

      # Whose cookie keeps the token for the next request: :app or :clowk.
      #
      # Both are cookies — that is why the setting names the OWNER rather than
      # the mechanism. :clowk is this gem's own cookie; :app is the Rails
      # session, which is itself one cookie carrying everything the app puts in
      # `session[...]`.
      #
      # Clowk's own cookie is written either way — it is what `current_token`
      # reads when the session has none, and the only place an API-only app has
      # ever had. The setting decides whether a COPY is also mirrored into the
      # app's Rails session, as every version before 0.9 did.
      #
      # That copy is not free. A Rails session lives in ONE cookie with about
      # 4096 bytes to its name, and in production, where tokens are RS256, the
      # token is most of what a session weighs. Hand a browser more than it will
      # hold and it discards the whole cookie in silence: no error server-side,
      # none in the console, the previous cookie simply stays. Everything written
      # on that request goes with it — a flash message, a selected tenant — which
      # reads as a button that does nothing.
      #
      # :session stays the default so an upgrade changes nothing until an app
      # asks for :cookie.
      @token_store = :app
    end

    # Where API-only apps cache session status, since they have no Rails session
    # to hang it on. Defaults to Rails.cache when Rails is loaded; set to nil to
    # check with Clowk on every authenticated request.
    def session_status_cache
      return @session_status_cache if defined?(@session_status_cache)

      @session_status_cache = (defined?(::Rails) && ::Rails.respond_to?(:cache)) ? ::Rails.cache : nil
    end

    # Defaults to the publishable key, which is what Clowk stamps into `aud`.
    # Consumers already configure that key, so audience checking is on by
    # default rather than something you have to know to switch on.
    def audience
      @audience.nil? ? @publishable_key : @audience
    end

    def after_sign_in_path
      resolve_path(@after_sign_in_path)
    end

    def after_sign_out_path
      resolve_path(@after_sign_out_path)
    end

    attr_writer :after_sign_in_path

    attr_writer :after_sign_out_path

    def validate!
      errors = []
      errors << "secret_key must be a String" unless @secret_key.is_a?(String) || @secret_key.nil?
      errors << "http_open_timeout must be Numeric" unless @http_open_timeout.is_a?(Numeric)
      errors << "http_read_timeout must be Numeric" unless @http_read_timeout.is_a?(Numeric)
      errors << "http_write_timeout must be Numeric" unless @http_write_timeout.is_a?(Numeric)
      errors << "http_retry_attempts must be a non-negative Integer" unless @http_retry_attempts.is_a?(Integer) && @http_retry_attempts >= 0
      errors << "session_status_ttl must be a non-negative Integer" unless @session_status_ttl.is_a?(Integer) && @session_status_ttl >= 0

      raise ConfigurationError, errors.join(", ") if errors.any?

      true
    end

    private

    def resolve_path(path_or_callable)
      path_or_callable.respond_to?(:call) ? path_or_callable.call : path_or_callable
    end
  end
end
