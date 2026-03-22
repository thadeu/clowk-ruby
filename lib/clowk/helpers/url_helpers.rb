# frozen_string_literal: true

require 'cgi'

module Clowk
  module Helpers
    module UrlHelpers
      def clowk_sign_in_path(return_to: nil)
        append_query(clowk_local_path('/sign_in'), return_to:)
      end

      def clowk_sign_up_path(return_to: nil)
        append_query(clowk_local_path('/sign_up'), return_to:)
      end

      def clowk_sign_out_path(return_to: nil)
        append_query(clowk_local_path('/sign_out'), return_to:)
      end

      def clowk_callback_url(return_to: nil)
        append_query("#{request.base_url}#{Clowk.config.callback_path}", return_to:)
      end

      def clowk_sign_in_url(redirect_to: nil, return_to: nil)
        clowk_remote_auth_url('sign-in', redirect_to:, return_to:)
      end

      def clowk_sign_up_url(redirect_to: nil, return_to: nil)
        clowk_remote_auth_url('sign-up', redirect_to:, return_to:)
      end

      private

      def clowk_remote_auth_url(action, redirect_to:, return_to:)
        callback_url = clowk_callback_url(return_to: redirect_to || return_to)
        query = { redirect_uri: callback_url }

        append_query("#{clowk_instance_base_url}/#{action}", query)
      end

      def clowk_instance_base_url
        return Clowk.config.instance_url if Clowk.config.instance_url.present?

        return "#{Clowk.config.app_base_url}/i/#{Clowk.config.publishable_key}" if Clowk.config.publishable_key.present?

        raise ConfigurationError, 'set instance_url or publishable_key to build Clowk URLs'
      end

      def clowk_local_path(path)
        "#{Clowk.config.mount_path}#{path}"
      end

      def append_query(url, params = {})
        filtered = params.compact.reject { |_key, value| value.respond_to?(:empty?) && value.empty? }
        return url if filtered.empty?

        separator = url.include?('?') ? '&' : '?'
        "#{url}#{separator}#{Rack::Utils.build_query(filtered)}"
      end
    end
  end
end
