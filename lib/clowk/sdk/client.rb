# frozen_string_literal: true

require 'active_support/inflector'

module Clowk
  module SDK
    class Client
      def initialize(options = {})
        @api_base_url = options.fetch(:api_base_url, Clowk.config.api_base_url)
        @secret_key = options.fetch(:secret_key, Clowk.config.secret_key)
        @publishable_key = options.fetch(:publishable_key, Clowk.config.publishable_key)
      end

      def method_missing(method_name, *, **, &)
        resource_class_name = ActiveSupport::Inflector.camelize(
          ActiveSupport::Inflector.singularize(method_name.to_s)
        )

        return super unless Clowk::SDK.const_defined?(resource_class_name)

        resource_ivar = "@#{method_name}"
        return instance_variable_get(resource_ivar) if instance_variable_defined?(resource_ivar)

        resource_class = Clowk::SDK.const_get(resource_class_name)
        instance_variable_set(resource_ivar, resource_class.new(self))
      end

      def respond_to_missing?(method_name, include_private = false)
        resource_class_name = ActiveSupport::Inflector.camelize(
          ActiveSupport::Inflector.singularize(method_name.to_s)
        )

        Clowk::SDK.const_defined?(resource_class_name) || super
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
end
