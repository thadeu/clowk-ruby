# frozen_string_literal: true

require 'rails'
require 'rails/engine'
require 'action_controller/railtie'
require 'active_support'
require 'active_support/core_ext/hash'
require 'active_support/core_ext/object/blank'
require 'rack'

require_relative 'clowk/version'
require_relative 'clowk/configuration'

module Clowk
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class InvalidStateError < Error; end
  class InvalidTokenError < Error; end

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield(config)
    end

    def reset!
      Subdomain.clear_cache! if defined?(Subdomain)
      @config = Configuration.new
    end
  end
end

require_relative 'clowk/current'
require_relative 'clowk/http/response'
require_relative 'clowk/http/logger_middleware'
require_relative 'clowk/http/retry_middleware'
require_relative 'clowk/http/timeout_middleware'
require_relative 'clowk/http/client'
require_relative 'clowk/subdomain'
require_relative 'clowk/jwt_verifier'
require_relative 'clowk/sdk/resourceable'
require_relative 'clowk/helpers/url_helpers'
require_relative 'clowk/middleware/token_extractor'
require_relative 'clowk/authenticable'
require_relative 'clowk/client'
require_relative 'clowk/controllers/base_controller'
require_relative 'clowk/controllers/callbacks_controller'
require_relative 'clowk/controllers/sessions_controller'
require_relative 'clowk/engine'
