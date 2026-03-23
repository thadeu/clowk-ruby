# frozen_string_literal: true

require 'uri'

module Clowk
  class Subdomain
    API_BASE_URL = 'https://api.clowk.dev/api/v1'
    CACHE_TTL = 60
    DEFAULT_SUBDOMAIN_BASE = 'clowk.dev'

    class << self
      def resolve_url!(...)
        new(...).resolve_url!
      end

      def clear_cache!
        @cache = {}
      end

      def read_cache(key)
        entry = cache[key]

        return unless entry
        return entry[:value] if entry[:expires_at] > Time.now

        cache.delete(key)
        nil
      end

      def write_cache(key, value, ttl:)
        cache[key] = {
          value: value,
          expires_at: Time.now + ttl
        }
      end

      private

      def cache
        @cache ||= {}
      end
    end

    def initialize(options = {})
      @publishable_key = options.fetch(:publishable_key, Clowk.config.publishable_key)
      @subdomain_url = options.fetch(:subdomain_url, Clowk.config.subdomain_url)
    end

    def resolve_url!
      return resolve_from_key if publishable_key.present?
      return normalize_url(subdomain_url) if subdomain_url.present?

      raise ConfigurationError, 'set publishable_key or subdomain_url to build Clowk URLs'
    end

    private

    attr_reader :publishable_key, :subdomain_url

    def resolve_from_key
      cached = self.class.read_cache(cache_key)
      return cached if cached

      response = client.subdomains.find_by_pk(publishable_key)
      resolved = extract_url_from_instance(response.body_parsed)

      raise ConfigurationError, 'could not resolve subdomain_url from publishable_key' if resolved.blank?

      self.class.write_cache(cache_key, resolved, ttl: CACHE_TTL)
      resolved
    end

    def cache_key
      "instance-url:#{publishable_key}"
    end

    def extract_url_from_instance(payload)
      return if payload.blank?

      root = payload.is_a?(Hash) ? payload : {}
      instance_data = if root['instance'].is_a?(Hash)
                        root['instance']
                      elsif root['data'].is_a?(Hash)
                        root['data']
                      else
                        root
                      end

      explicit_url = instance_data['url'] || instance_data['subdomain_url'] || instance_data['instance_url']
      return normalize_url(explicit_url) if explicit_url.present?

      host = instance_data['host'] || instance_data['domain'] || instance_data['hostname']
      return normalize_url(host_to_url(host)) if host.present?

      subdomain = instance_data['subdomain']
      normalize_url("https://#{subdomain}.#{default_subdomain_base}") if subdomain.present?
    end

    def host_to_url(host)
      value = host.to_s
      return value if value.start_with?('http://', 'https://')

      "https://#{value}"
    end

    def default_subdomain_base
      configured = subdomain_url.to_s.strip
      return DEFAULT_SUBDOMAIN_BASE if configured.empty?

      uri = URI.parse(configured)
      return DEFAULT_SUBDOMAIN_BASE if uri.host.blank?

      uri.host.split('.').drop(1).join('.')
    rescue URI::InvalidURIError
      DEFAULT_SUBDOMAIN_BASE
    end

    def normalize_url(value)
      value.to_s.sub(%r{/$}, '')
    end

    def client
      @client ||= Clowk::SDK::Client.new(api_base_url: API_BASE_URL)
    end
  end
end
