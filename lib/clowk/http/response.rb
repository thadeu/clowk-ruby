# frozen_string_literal: true

module Clowk
  class Http
    class Response
      attr_reader :body, :body_parsed, :headers, :status

      def initialize(status:, body:, body_parsed:, headers:, success:)
        @status = status
        @body = body
        @body_parsed = body_parsed
        @headers = headers
        @success = success
      end

      def success?
        @success
      end

      def [](key)
        to_h.fetch(key)
      end

      def to_h
        {
          status: status,
          body: body,
          body_parsed: body_parsed,
          headers: headers,
          success?: success?
        }
      end

      def ==(other)
        if other.respond_to?(:to_h)
          to_h == other.to_h
        else
          to_h == other
        end
      end
    end
  end
end