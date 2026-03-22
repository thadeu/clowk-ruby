# frozen_string_literal: true

module Clowk
  class Http
    class TimeoutMiddleware
      def initialize(app, logger: nil, open_timeout: nil, read_timeout: nil, write_timeout: nil, **)
        @app = app
        @logger = logger || LoggerMiddleware::NullLogger.new
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @write_timeout = write_timeout
      end

      def call(env)
        env[:timeouts] = {
          open_timeout: env.fetch(:open_timeout, open_timeout),
          read_timeout: env.fetch(:read_timeout, read_timeout),
          write_timeout: env.fetch(:write_timeout, write_timeout)
        }.compact

        logger.info("[Clowk::Http] timeouts=#{env[:timeouts]}") unless env[:timeouts].empty?
        app.call(env)
      end

      private

      attr_reader :app, :logger, :open_timeout, :read_timeout, :write_timeout
    end
  end
end