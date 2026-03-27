# frozen_string_literal: true

module Clowk
  module SDK
    class Token < Resource
      def self.resource_path
        'tokens'
      end

      def verify(token:)
        client.post("#{self.class.resource_path}/verify", { token: token })
      end

      def verify_with_session(token:)
        response = verify(token:)
        data = response.body_parsed&.dig('data') || response.body_parsed

        data&.deep_symbolize_keys
      end
    end
  end
end
