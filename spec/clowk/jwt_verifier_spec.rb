# frozen_string_literal: true

require 'jwt'

RSpec.describe Clowk::JwtVerifier do
  let(:secret_key) { 'test_secret_key' }
  let(:issuer) { 'clowk' }

  subject(:verifier) { described_class.new(secret_key: secret_key, issuer: issuer) }

  def encode_token(payload, key: secret_key, algorithm: 'HS256')
    JWT.encode(payload, key, algorithm)
  end

  describe '#verify' do
    it 'decodes a valid token' do
      token = encode_token({ sub: 'user_123', iss: issuer })

      result = verifier.verify(token)

      expect(result[:sub]).to eq('user_123')
      expect(result[:iss]).to eq('clowk')
    end

    it 'raises ConfigurationError when secret_key is missing' do
      verifier = described_class.new(secret_key: nil, issuer: issuer)

      expect { verifier.verify('any_token') }.to raise_error(Clowk::ConfigurationError, /missing Clowk secret_key/)
    end

    it 'raises ConfigurationError when secret_key is empty' do
      verifier = described_class.new(secret_key: '', issuer: issuer)

      expect { verifier.verify('any_token') }.to raise_error(Clowk::ConfigurationError, /missing Clowk secret_key/)
    end

    it 'raises InvalidTokenError for an expired token' do
      token = encode_token({ sub: 'user_123', iss: issuer, exp: Time.now.to_i - 3600 })

      expect { verifier.verify(token) }.to raise_error(Clowk::InvalidTokenError, /Signature has expired/)
    end

    it 'raises InvalidTokenError for a malformed token' do
      expect { verifier.verify('not.a.valid.jwt') }.to raise_error(Clowk::InvalidTokenError)
    end

    it 'raises InvalidTokenError for a completely garbage string' do
      expect { verifier.verify('garbage') }.to raise_error(Clowk::InvalidTokenError)
    end

    it 'raises InvalidTokenError when signed with the wrong key' do
      token = encode_token({ sub: 'user_123', iss: issuer }, key: 'wrong_key')

      expect { verifier.verify(token) }.to raise_error(Clowk::InvalidTokenError)
    end

    it 'raises InvalidTokenError when issuer does not match' do
      token = encode_token({ sub: 'user_123', iss: 'other_issuer' })

      expect { verifier.verify(token) }.to raise_error(Clowk::InvalidTokenError, /Invalid issuer/)
    end

    it 'skips issuer verification when issuer is nil' do
      verifier = described_class.new(secret_key: secret_key, issuer: nil)
      token = encode_token({ sub: 'user_123', iss: 'anything' })

      result = verifier.verify(token)

      expect(result[:sub]).to eq('user_123')
    end

    it 'accepts a token that is not yet expired' do
      token = encode_token({ sub: 'user_123', iss: issuer, exp: Time.now.to_i + 3600 })

      result = verifier.verify(token)

      expect(result[:sub]).to eq('user_123')
    end
  end
end
