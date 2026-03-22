# frozen_string_literal: true

module Clowk
  module Client
    class SDK
      def initialize(api_base_url: Clowk.config.api_base_url, secret_key: Clowk.config.secret_key, publishable_key: Clowk.config.publishable_key)
        @api_base_url = api_base_url
        @secret_key = secret_key
        @publishable_key = publishable_key
      end

      def verify_token(token:)
        post('tokens/verify', { token: token })
      end

      def user(id)
        get("users/#{id}")
      end

      def delete(path, body = nil, headers: {})
        http.delete(path, body, headers:)
      end

      def patch(path, body = {}, headers: {})
        http.patch(path, body, headers:)
      end

      def get(path, headers: {})
        http.get(path, headers:)
      end

      def post(path, body = {}, headers: {})
        http.post(path, body, headers:)
      end

      def put(path, body = {}, headers: {})
        http.put(path, body, headers:)
      end

      def head(path, headers: {})
        http.head(path, headers:)
      end

      def options(path, headers: {})
        http.options(path, headers:)
      end

      private

      attr_reader :api_base_url, :publishable_key, :secret_key

      def http
        @http ||= Clowk::Http.new(
          base_url: api_base_url,
          headers: default_headers,
          logger: Clowk.config.http_logger,
          open_timeout: Clowk.config.http_open_timeout,
          read_timeout: Clowk.config.http_read_timeout,
          write_timeout: Clowk.config.http_write_timeout,
          retry_attempts: Clowk.config.http_retry_attempts,
          retry_interval: Clowk.config.http_retry_interval
        )
      end

      def default_headers
        {}.tap do |headers|
          headers['X-Clowk-Secret-Key'] = secret_key if secret_key.present?
          headers['X-Clowk-Publishable-Key'] = publishable_key if publishable_key.present?
        end
      end
    end
  end

  SDK = Client::SDK
end
