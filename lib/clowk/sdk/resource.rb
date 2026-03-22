# frozen_string_literal: true

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

      # Usage
      # client.search("publishable_key_eq=pk_test_123")
      # @return [Array<Hash>] list of resources matching the query
      def search(query)
        client.get("#{self.class.resource_path}/search?q=#{query}")
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
