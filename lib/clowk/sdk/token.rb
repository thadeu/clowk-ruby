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
    end
  end
end
