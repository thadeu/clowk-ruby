# frozen_string_literal: true

module Clowk
  class Configuration
    attr_accessor :api_base_url
    attr_accessor :app_base_url
    attr_accessor :after_sign_in_path
    attr_accessor :after_sign_out_path
    attr_accessor :callback_path
    attr_accessor :cookie_key
    attr_accessor :http_logger
    attr_accessor :http_open_timeout
    attr_accessor :http_read_timeout
    attr_accessor :http_retry_attempts
    attr_accessor :http_retry_interval
    attr_accessor :http_write_timeout
    attr_accessor :issuer
    attr_accessor :mount_path
    attr_accessor :publishable_key
    attr_accessor :prefix_by
    attr_accessor :secret_key
    attr_accessor :session_key
    attr_accessor :subdomain_url
    attr_accessor :token_param

    def initialize
      @api_base_url = 'https://api.clowk.dev/client/v1'
      @app_base_url = 'https://app.clowk.in'
      @after_sign_in_path = '/'
      @after_sign_out_path = '/'
      @mount_path = '/clowk'
      @callback_path = '/clowk/oauth/callback'
      @cookie_key = 'clowk_token'
      @http_logger = nil
      @http_open_timeout = 5
      @http_read_timeout = 10
      @http_retry_attempts = 2
      @http_retry_interval = 0.05
      @http_write_timeout = 10
      @issuer = 'clowk'
      @session_key = :clowk
      @prefix_by = :clowk
      @token_param = :token
    end
  end
end
