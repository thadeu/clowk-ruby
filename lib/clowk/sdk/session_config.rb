# frozen_string_literal: true

module Clowk
  module SDK
    class SessionConfig < Resource
      def self.resource_path
        "session_config"
      end

      def fetch
        response = client.get(self.class.resource_path)

        response.body_parsed&.deep_symbolize_keys
      end
    end
  end
end
