# frozen_string_literal: true

module Clowk
  class SDK
    class Token
      def self.resource_path
        'tokens'
      end

      def initialize(client)
        @client = client
      end

      def verify(token:)
        client.post("#{self.class.resource_path}/verify", { token: token })
      end

      private

      attr_reader :client
    end
  end
end
