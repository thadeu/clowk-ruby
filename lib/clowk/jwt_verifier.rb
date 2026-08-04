# frozen_string_literal: true

require "jwt"

module Clowk
  class JwtVerifier
    LEGACY_ALGORITHM = "HS256"
    ASYMMETRIC_ALGORITHM = "RS256"

    # Kept because it is part of the gem's public surface. Prefer
    # LEGACY_ALGORITHM — this no longer describes what the verifier accepts.
    ALGORITHM = LEGACY_ALGORITHM

    def initialize(secret_key: Clowk.config.secret_key, issuer: Clowk.config.issuer,
      audience: Clowk.config.audience, jwks_url: Clowk.config.jwks_url)
      @secret_key = secret_key
      @issuer = issuer
      @audience = audience
      @jwks_url = jwks_url
    end

    def verify(token)
      payload, = asymmetric?(token) ? verify_asymmetric(token) : verify_legacy(token)
      payload.deep_symbolize_keys
    rescue JWT::DecodeError, JWT::VerificationError, JWT::ExpiredSignature,
      JWT::InvalidIssuerError, JWT::InvalidAudError => e
      raise InvalidTokenError, e.message
    end

    private

    def asymmetric?(token)
      header(token)["alg"] == ASYMMETRIC_ALGORITHM
    rescue JWT::DecodeError
      false
    end

    def header(token)
      JWT.decode(token, nil, false).last
    end

    # Tokens signed with the shared instance secret. Kept so tokens issued
    # before the RS256 migration keep working until they expire.
    def verify_legacy(token)
      raise ConfigurationError, "missing Clowk secret_key" if @secret_key.to_s.empty?

      JWT.decode(token, @secret_key, true, base_options.merge(algorithm: LEGACY_ALGORITHM))
    end

    def verify_asymmetric(token)
      kid = header(token)["kid"]

      raise InvalidTokenError, "token is missing kid header" if kid.to_s.empty?

      key = Jwks.key_for(kid, jwks_url: @jwks_url)

      raise InvalidTokenError, "unknown signing key: #{kid}" unless key

      JWT.decode(token, key, true, asymmetric_options)
    end

    def base_options
      opts = {}

      if @issuer
        opts[:iss] = @issuer
        opts[:verify_iss] = true
      end

      opts
    end

    # Audience is enforced only here, and deliberately so. Under RS256 every
    # consumer trusts the same public key, so without `aud` a token minted for
    # another app would verify cleanly — the shared secret used to prevent that
    # by accident. HS256 tokens are already scoped by the per-instance secret,
    # and the ones issued before this claim existed carry no `aud` at all, so
    # enforcing it there would reject valid tokens during the migration window.
    def asymmetric_options
      opts = base_options.merge(algorithm: ASYMMETRIC_ALGORITHM)

      if @audience
        opts[:aud] = @audience
        opts[:verify_aud] = true
      end

      opts
    end
  end
end
