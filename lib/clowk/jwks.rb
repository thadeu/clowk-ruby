# frozen_string_literal: true

require "base64"
require "json"
require "openssl"
require "uri"

module Clowk
  # Fetches and caches Clowk's public key set.
  #
  # Keys are cached process-wide because verifying a token must not cost an
  # HTTP round trip. A `kid` the cache has never seen forces one refetch — that
  # is what makes key rotation invisible to consumers instead of an outage.
  class Jwks
    CACHE_TTL = 600
    WELL_KNOWN_PATH = "/.well-known/jwks.json"

    # Rotation should resolve in one refetch. Anything beyond that is a
    # misconfigured issuer or a forged `kid`, and hammering the auth server on
    # every unverifiable token turns a bad token into an outage.
    REFETCH_COOLDOWN = 10

    @cache_mutex = Mutex.new

    class << self
      def clear_cache!
        @cache_mutex.synchronize do
          @cache = {}
          @last_refetch_at = {}
        end
      end

      def key_for(kid, jwks_url: Clowk.config.jwks_url)
        url = jwks_url || default_url

        key = lookup(url, kid)
        return key if key

        # Cold or expired cache: this is the ordinary first fetch, not a
        # rotation, so it must not spend the miss budget. Data is fresh
        # afterwards, so a miss here means the kid is genuinely unknown.
        return fetch_and_lookup(url, kid) unless warm?(url)

        # Warm cache and an unknown kid: the set may have rotated under us.
        return nil unless claim_refetch_slot!(url)

        fetch_and_lookup(url, kid)
      end

      def default_url
        base = Clowk.config.subdomain_url || Clowk::Subdomain.resolve_url!

        "#{base.to_s.chomp("/")}#{WELL_KNOWN_PATH}"
      rescue ConfigurationError
        raise ConfigurationError, "set jwks_url, subdomain_url or publishable_key to verify RS256 tokens"
      end

      private

      def fetch_and_lookup(url, kid)
        fetch!(url)
        lookup(url, kid)
      end

      def warm?(url)
        @cache_mutex.synchronize do
          entry = cache[url]

          !entry.nil? && entry[:expires_at] > Time.now
        end
      end

      def lookup(url, kid)
        @cache_mutex.synchronize do
          entry = cache[url]

          next nil unless entry
          next nil if entry[:expires_at] <= Time.now

          entry[:keys][kid]
        end
      end

      # Throttles only the refetches a cache miss triggers, not ordinary TTL
      # refreshes. A rotation is picked up on the very next token; a storm of
      # forged kids costs at most one fetch per cooldown window.
      def claim_refetch_slot!(url)
        @cache_mutex.synchronize do
          last = last_refetch_at[url]

          next false if last && Time.now - last < REFETCH_COOLDOWN

          last_refetch_at[url] = Time.now
          true
        end
      end

      def fetch!(url)
        uri = URI.parse(url)
        base = uri.dup
        base.path = ""
        base.query = nil
        base.fragment = nil

        response = Http.get(base_url: base.to_s, path: uri.path, logger: Clowk.config.http_logger)

        raise InvalidTokenError, "could not fetch JWKS from #{url}" unless response.success?

        keys = parse(response.body)

        @cache_mutex.synchronize do
          cache[url] = {keys: keys, expires_at: Time.now + CACHE_TTL}
        end

        keys
      end

      def parse(body)
        payload = body.is_a?(Hash) ? body : JSON.parse(body.to_s)
        entries = payload["keys"] || payload[:keys] || []

        entries.each_with_object({}) do |jwk, acc|
          jwk = jwk.transform_keys(&:to_s)
          next unless jwk["kty"] == "RSA" && jwk["kid"]

          acc[jwk["kid"]] = to_rsa(jwk)
        end
      rescue JSON::ParserError => e
        raise InvalidTokenError, "malformed JWKS document: #{e.message}"
      end

      # Built through DER rather than assigning n/e onto a blank key: OpenSSL 3
      # made key objects immutable, so `set_key` no longer exists.
      def to_rsa(jwk)
        sequence = OpenSSL::ASN1::Sequence([
          OpenSSL::ASN1::Integer(decode_bn(jwk["n"])),
          OpenSSL::ASN1::Integer(decode_bn(jwk["e"]))
        ])

        OpenSSL::PKey::RSA.new(sequence.to_der)
      end

      def decode_bn(value)
        OpenSSL::BN.new(Base64.urlsafe_decode64(pad(value.to_s)), 2)
      end

      # JWKS values are unpadded base64url; Ruby's decoder wants padding.
      def pad(value)
        remainder = value.length % 4

        remainder.zero? ? value : value + ("=" * (4 - remainder))
      end

      def cache
        @cache ||= {}
      end

      def last_refetch_at
        @last_refetch_at ||= {}
      end
    end
  end
end
