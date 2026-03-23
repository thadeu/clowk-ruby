# frozen_string_literal: true

module Clowk
  module SDK
    class Session < Resource
      def self.resource_path
        'sessions'
      end

      # @param email [String] Email to search for (ILIKE match)
      # @return [Clowk::Http::Response]
      def search(email:)
        client.get("#{self.class.resource_path}/search?email=#{ERB::Util.url_encode(email)}")
      end

      # Revokes a session by its session_id (clk_session_UUID)
      # @param session_id [String]
      # @return [Clowk::Http::Response]
      def revoke(session_id)
        destroy(session_id)
      end
    end
  end
end
