# frozen_string_literal: true

module Clowk
  class SDK
    class Subdomain < Resource
      def self.resource_path
        'instances'
      end

      def find_by_pk(key = nil)
        return if key.blank?

        client.search("publishable_key_eq=#{key}")
      end
    end
  end
end
