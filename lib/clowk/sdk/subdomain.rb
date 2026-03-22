# frozen_string_literal: true

module Clowk
  module SDK
    class Subdomain < Resource
      def self.resource_path
        'instances'
      end

      def find_by_pk(key = nil)
        return if key.blank?

        search(publishable_key: key)
      end
    end
  end
end
