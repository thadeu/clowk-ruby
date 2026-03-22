# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module Clowk
  class Http
    HTTP_METHODS = {
      get: Net::HTTP::Get,
      post: Net::HTTP::Post,
      put: Net::HTTP::Put,
      patch: Net::HTTP::Patch,
      delete: Net::HTTP::Delete,
      head: Net::HTTP::Head,
      options: Net::HTTP::Options
    }.freeze

    def self.get(base_url:, path:, headers: {}, logger: nil)
      new(base_url:, headers:, logger:).get(path)
    end

    def self.post(base_url:, path:, body: nil, headers: {}, logger: nil)
      new(base_url:, headers:, logger:).post(path, body)
    end

    def self.put(base_url:, path:, body: nil, headers: {}, logger: nil)
      new(base_url:, headers:, logger:).put(path, body)
    end

    def self.patch(base_url:, path:, body: nil, headers: {}, logger: nil)
      new(base_url:, headers:, logger:).patch(path, body)
    end

    def self.delete(base_url:, path:, body: nil, headers: {}, logger: nil)
      new(base_url:, headers:, logger:).delete(path, body)
    end

    def self.head(base_url:, path:, headers: {}, logger: nil)
      new(base_url:, headers:, logger:).head(path)
    end

    def self.options(base_url:, path:, headers: {}, logger: nil)
      new(base_url:, headers:, logger:).options(path)
    end

    def initialize(base_url:, headers: {}, logger: nil, open_timeout: 5, read_timeout: 10, write_timeout: 10, retry_attempts: 2, retry_interval: 0.05, middlewares: nil)
      @base_url = base_url
      @headers = headers
      @logger = logger
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @write_timeout = write_timeout
      @retry_attempts = retry_attempts
      @retry_interval = retry_interval
      @middlewares = middlewares || [TimeoutMiddleware, RetryMiddleware, LoggerMiddleware]
    end

    def get(path, headers: {})
      request(:get, path, headers:)
    end

    def post(path, body = nil, headers: {})
      request(:post, path, body:, headers:)
    end

    def put(path, body = nil, headers: {})
      request(:put, path, body:, headers:)
    end

    def patch(path, body = nil, headers: {})
      request(:patch, path, body:, headers:)
    end

    def delete(path, body = nil, headers: {})
      request(:delete, path, body:, headers:)
    end

    def head(path, headers: {})
      request(:head, path, headers:)
    end

    def options(path, headers: {})
      request(:options, path, headers:)
    end

    def request(method, path, body: nil, headers: {})
      env = {
        method: method.to_sym,
        uri: build_uri(path),
        body: body,
        headers: headers,
        open_timeout: open_timeout,
        read_timeout: read_timeout,
        write_timeout: write_timeout,
        retry_attempts: retry_attempts,
        retry_interval: retry_interval
      }

      build_stack.call(env)
    end

    private

    attr_reader :base_url, :headers, :logger, :middlewares, :open_timeout, :read_timeout, :write_timeout, :retry_attempts, :retry_interval

    def build_stack
      app = lambda { |env| perform_request(env) }

      middlewares.reverse.inject(app) do |next_app, middleware|
        middleware.new(next_app, logger:, open_timeout:, read_timeout:, write_timeout:)
      end
    end

    def perform_request(env)
      request = request_class_for(env[:method]).new(env[:uri])

      apply_headers(request, env[:headers])

      request.body = JSON.generate(env[:body]) unless env[:body].nil?

      raw_response = Net::HTTP.start(env[:uri].host, env[:uri].port, use_ssl: env[:uri].scheme == 'https') do |http|
        apply_timeouts(http, env[:timeouts])
        http.request(request)
      end

      parse_response(raw_response)
    end

    def request_class_for(method)
      HTTP_METHODS.fetch(method.to_sym) do
        raise ArgumentError, "unsupported HTTP method: #{method}"
      end
    end

    def build_uri(path)
      base_uri = URI(base_url)
      base_uri.path = join_paths(base_uri.path, normalize_path(path))
      base_uri.query = nil
      base_uri.fragment = nil
      base_uri
    end

    def normalize_path(path)
      path.to_s.start_with?('/') ? path : "/#{path}"
    end

    def join_paths(base_path, extra_path)
      segments = [base_path.to_s, extra_path.to_s].map { |segment| segment.gsub(%r{^/+|/+$}, '') }.reject(&:empty?)
      "/#{segments.join('/')}"
    end

    def apply_headers(request, request_headers)
      merged_headers = default_headers.merge(headers).merge(request_headers)
      merged_headers.each { |key, value| request[key] = value }
    end

    def apply_timeouts(http, timeouts)
      return unless timeouts

      http.open_timeout = timeouts[:open_timeout] if timeouts.key?(:open_timeout)
      http.read_timeout = timeouts[:read_timeout] if timeouts.key?(:read_timeout)
      http.write_timeout = timeouts[:write_timeout] if timeouts.key?(:write_timeout) && http.respond_to?(:write_timeout=)
    end

    def default_headers
      {
        'Accept' => 'application/json',
        'Content-Type' => 'application/json'
      }
    end

    def parse_response(response)
      body = response.body.to_s
      parsed = parse_body(body)

      {
        status: response.code.to_i,
        body: body,
        body_parsed: parsed,
        headers: response.to_hash,
        success?: response.is_a?(Net::HTTPSuccess)
      }
    end

    def parse_body(body)
      return {} if body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end
  end
end
