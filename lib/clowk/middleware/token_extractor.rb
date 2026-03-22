# frozen_string_literal: true

module Clowk
  module Middleware
    class TokenExtractor
      def initialize(request, token_param: Clowk.config.token_param, cookie_key: Clowk.config.cookie_key)
        @request = request
        @token_param = token_param
        @cookie_key = cookie_key
      end

      def call
        token_from_params || token_from_bearer || token_from_cookies
      end

      private

      attr_reader :request, :token_param, :cookie_key

      def token_from_params
        params = request.respond_to?(:params) && request.params ? request.params : {}
        params[token_param.to_s].presence
      end

      def token_from_bearer
        header = request.authorization.to_s
        return if header.empty?

        scheme, token = header.split(' ', 2)
        return unless scheme.to_s.casecmp('Bearer').zero?

        token.presence
      end

      def token_from_cookies
        return unless request.respond_to?(:cookie_jar) && request.cookie_jar

        request.cookie_jar[cookie_key].presence
      end
    end
  end
end
