# frozen_string_literal: true

require 'uri'

module Clowk
  class Subdomain
    CACHE_TTL = 60
    REDIRECT_CODES = [301, 302, 303, 307, 308].freeze
    MAX_REDIRECTS = 5

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

    def initialize(publishable_key: Clowk.config.publishable_key, instance_url: Clowk.config.instance_url, app_base_url: Clowk.config.app_base_url)
      @publishable_key = publishable_key
      @instance_url = instance_url
      @app_base_url = app_base_url
    end

    def resolve_url!
      return resolve_from_key if publishable_key.present?
      return normalize_url(instance_url) if instance_url.present?

      raise ConfigurationError, 'set publishable_key or instance_url to build Clowk URLs'
    end

    private

    attr_reader :app_base_url, :instance_url, :publishable_key

    def resolve_from_key
      cached = self.class.read_cache(cache_key)
      return cached if cached

      resolved = follow(locator_path)
      self.class.write_cache(cache_key, resolved, ttl: CACHE_TTL)
      resolved
    end

    def cache_key
      "instance-url:#{publishable_key}"
    end

    def locator_path
      "i/#{publishable_key}"
    end

    def follow(path, redirects_left = MAX_REDIRECTS)
      response = sdk.instances.find_by_key(path:)
      return normalize_resolved_url(path) unless REDIRECT_CODES.include?(response.status)

      location = response.headers['location']&.first

      raise ConfigurationError, 'could not resolve instance_url from publishable_key' if location.blank?
      raise ConfigurationError, 'too many redirects resolving instance_url' if redirects_left <= 0

      follow(next_path(path, location), redirects_left - 1)
    end

    def next_path(current_path, location)
      current_uri = URI.join("#{app_base_url}/", current_path)
      next_uri = URI.join(current_uri.to_s, location)

      if next_uri.host == URI.parse(app_base_url).host
        next_uri.request_uri.delete_prefix('/')
      else
        next_uri.to_s
      end
    end

    def normalize_resolved_url(path)
      resolved_uri = URI.join("#{app_base_url}/", path)

      app_base_uri = URI.parse(app_base_url)
      return normalize_url(instance_url) if instance_url.present? && resolved_uri.host == app_base_uri.host && resolved_uri.path.start_with?('/i/')

      normalized = URI.parse(resolved_uri.to_s)
      normalized.path = ''
      normalized.query = nil
      normalized.fragment = nil

      normalize_url(normalized.to_s)
    end

    def normalize_url(value)
      value.to_s.sub(%r{/$}, '')
    end

    def sdk
      @sdk ||= Clowk::SDK.new(api_base_url: app_base_url)
    end
  end
end