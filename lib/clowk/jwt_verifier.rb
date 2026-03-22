# frozen_string_literal: true

require 'jwt'

module Clowk
  class JwtVerifier
    ALGORITHM = 'HS256'

    def initialize(secret_key: Clowk.config.secret_key, issuer: Clowk.config.issuer)
      @secret_key = secret_key
      @issuer = issuer
    end

    def verify(token)
      raise ConfigurationError, 'missing Clowk secret_key' if @secret_key.to_s.empty?

      options = { algorithm: ALGORITHM }
      options[:iss] = @issuer if @issuer
      options[:verify_iss] = @issuer.present?

      payload, = JWT.decode(token, @secret_key, true, options)
      payload.deep_symbolize_keys
    rescue JWT::DecodeError, JWT::VerificationError, JWT::ExpiredSignature, JWT::InvalidIssuerError => e
      raise InvalidTokenError, e.message
    end
  end
end
