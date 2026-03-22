# frozen_string_literal: true

require 'erb'

module Clowk
  module SDK
    class Resource
      def self.resource_path
        raise NotImplementedError, 'resource_path must be implemented'
      end

      def initialize(client)
        @client = client
      end

      # Usage
      # client.list
      # @return [Array<Hash>] list of all resources
      def list
        client.get(self.class.resource_path)
      end

      # @example
      #   client.subdomains.search(publishable_key: "pk_test_123", status: "active")
      #   # GET /instances/search?query=publishable_key:pk_test_123 status:active
      #
      # @param filters [Hash] key-value pairs to build the query
      # @return [Clowk::Http::Response]
      def search(**filters)
        query = filters.map { |k, v| "#{k}:#{v}" }.join(' ')

        client.get("#{self.class.resource_path}/search?query=#{ERB::Util.url_encode(query)}")
      end

      # Usage
      # client.find("123")
      # @return [Hash] resource with the given id
      def find(id)
        client.get("#{self.class.resource_path}/#{id}")
      end

      # Usage
      # client.show("123")
      # @return [Hash] resource with the given id
      def show(id:)
        client.get("#{self.class.resource_path}/#{id}")
      end

      # Usage
      # client.destroy("123")
      # @return [Hash] deleted resource
      def destroy(id)
        client.delete("#{self.class.resource_path}/#{id}")
      end

      private

      attr_reader :client
    end
  end
end
