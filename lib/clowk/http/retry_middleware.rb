# frozen_string_literal: true

require 'net/http'

module Clowk
  class Http
    class RetryMiddleware
      RETRYABLE_ERRORS = [
        EOFError,
        Errno::ECONNRESET,
        Errno::ETIMEDOUT,
        IOError,
        Net::OpenTimeout,
        Net::ReadTimeout,
        Net::WriteTimeout,
        SocketError
      ].freeze

      def initialize(app, logger: nil, **)
        @app = app
        @logger = logger || LoggerMiddleware::NullLogger.new
      end

      def call(env)
        attempts = env.fetch(:retry_attempts, 0)
        interval = env.fetch(:retry_interval, 0.0)
        current_attempt = 0

        begin
          current_attempt += 1
          env[:attempt] = current_attempt
          app.call(env)
        rescue *RETRYABLE_ERRORS => error
          raise error if current_attempt > attempts

          logger.info("[Clowk::Http] retry=#{current_attempt} error=#{error.class}")
          sleep(interval) if interval.positive?
          retry
        end
      end

      private

      attr_reader :app, :logger
    end
  end
end