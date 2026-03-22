# frozen_string_literal: true

require 'logger'

module Clowk
  class Http
    class LoggerMiddleware
      def initialize(app, logger: nil, **)
        @app = app
        @logger = logger || NullLogger.new
      end

      def call(env)
        logger.info("[Clowk::Http] #{env[:method].upcase} #{env[:uri]}")
        response = app.call(env)
        logger.info("[Clowk::Http] -> #{response[:status]}")
        response
      end

      private

      attr_reader :app, :logger

      class NullLogger
        def info(*); end
      end
    end
  end
end
