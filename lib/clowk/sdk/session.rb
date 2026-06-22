# frozen_string_literal: true

module Clowk
  module SDK
    class Session < Resource
      def self.resource_path
        "sessions"
      end

      # @param raw_query [String, nil] Raw query string (forwarded to the base search)
      # @param email [String, nil] Email to search for via the legacy ILIKE endpoint
      # @param filters [Hash] Keyword filters (forwarded to the base search)
      # @return [Clowk::Http::Response]
      def search(raw_query = nil, email: nil, **filters)
        return super(raw_query, **filters) unless email

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
