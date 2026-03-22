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

      # @example keywords
      #   client.users.search(email: "user@example.com", status: "active")
      #   # GET /users/search?query=email%3Auser%40example.com+status%3Aactive
      #
      # @example raw string
      #   client.users.search("email:user@example.com active:true created_at>2026-01-01")
      #   # GET /users/search?query=email%3Auser%40example.com+active%3Atrue+created_at%3E2026-01-01
      #
      # @return [Clowk::Http::Response]
      def search(raw_query = nil, **filters)
        query = if raw_query.is_a?(String)
                  raw_query
                else
                  filters.map { |k, v| "#{k}:#{v}" }.join(' ')
                end

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
      def show(id)
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
