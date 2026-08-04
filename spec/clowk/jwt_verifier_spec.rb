# frozen_string_literal: true

require "jwt"

RSpec.describe Clowk::JwtVerifier do
  let(:secret_key) { "test_secret_key" }
  let(:issuer) { "clowk" }

  subject(:verifier) { described_class.new(secret_key: secret_key, issuer: issuer) }

  def encode_token(payload, key: secret_key, algorithm: "HS256")
    JWT.encode(payload, key, algorithm)
  end

  describe "#verify" do
    it "decodes a valid token" do
      token = encode_token({sub: "user_123", iss: issuer})

      result = verifier.verify(token)

      expect(result[:sub]).to eq("user_123")
      expect(result[:iss]).to eq("clowk")
    end

    it "raises ConfigurationError when secret_key is missing" do
      verifier = described_class.new(secret_key: nil, issuer: issuer)

      expect { verifier.verify("any_token") }.to raise_error(Clowk::ConfigurationError, /missing Clowk secret_key/)
    end

    it "raises ConfigurationError when secret_key is empty" do
      verifier = described_class.new(secret_key: "", issuer: issuer)

      expect { verifier.verify("any_token") }.to raise_error(Clowk::ConfigurationError, /missing Clowk secret_key/)
    end

    it "raises InvalidTokenError for an expired token" do
      token = encode_token({sub: "user_123", iss: issuer, exp: Time.now.to_i - 3600})

      expect { verifier.verify(token) }.to raise_error(Clowk::InvalidTokenError, /Signature has expired/)
    end

    it "raises InvalidTokenError for a malformed token" do
      expect { verifier.verify("not.a.valid.jwt") }.to raise_error(Clowk::InvalidTokenError)
    end

    it "raises InvalidTokenError for a completely garbage string" do
      expect { verifier.verify("garbage") }.to raise_error(Clowk::InvalidTokenError)
    end

    it "raises InvalidTokenError when signed with the wrong key" do
      token = encode_token({sub: "user_123", iss: issuer}, key: "wrong_key")

      expect { verifier.verify(token) }.to raise_error(Clowk::InvalidTokenError)
    end

    it "raises InvalidTokenError when issuer does not match" do
      token = encode_token({sub: "user_123", iss: "other_issuer"})

      expect { verifier.verify(token) }.to raise_error(Clowk::InvalidTokenError, /Invalid issuer/)
    end

    it "skips issuer verification when issuer is nil" do
      verifier = described_class.new(secret_key: secret_key, issuer: nil)
      token = encode_token({sub: "user_123", iss: "anything"})

      result = verifier.verify(token)

      expect(result[:sub]).to eq("user_123")
    end

    it "accepts a token that is not yet expired" do
      token = encode_token({sub: "user_123", iss: issuer, exp: Time.now.to_i + 3600})

      result = verifier.verify(token)

      expect(result[:sub]).to eq("user_123")
    end
  end

  describe "RS256 tokens" do
    let(:rsa) { OpenSSL::PKey::RSA.generate(2048) }
    let(:kid) { "key-one" }
    let(:audience) { "pk_test_contagorda" }
    let(:jwks_url) { "https://auth.example.com/.well-known/jwks.json" }

    subject(:verifier) do
      described_class.new(secret_key: secret_key, issuer: issuer, audience: audience, jwks_url: jwks_url)
    end

    def rs256_token(payload, key: rsa, header: {kid: kid})
      JWT.encode({iss: issuer, aud: audience, exp: Time.now.to_i + 3600}.merge(payload), key, "RS256", header)
    end

    before { allow(Clowk::Jwks).to receive(:key_for).with(kid, jwks_url: jwks_url).and_return(rsa.public_key) }

    it "verifies against the key the kid points to" do
      result = verifier.verify(rs256_token({sub: "user_123"}))

      expect(result[:sub]).to eq("user_123")
    end

    # The gem must no longer need the signing secret to verify.
    it "verifies without a usable secret_key" do
      verifier = described_class.new(secret_key: nil, issuer: issuer, audience: audience, jwks_url: jwks_url)

      expect(verifier.verify(rs256_token({sub: "user_123"}))[:sub]).to eq("user_123")
    end

    it "rejects a token signed by a key that is not published" do
      stranger = OpenSSL::PKey::RSA.generate(2048)

      expect { verifier.verify(rs256_token({sub: "user_123"}, key: stranger)) }
        .to raise_error(Clowk::InvalidTokenError)
    end

    it "rejects a token whose kid is unknown" do
      allow(Clowk::Jwks).to receive(:key_for).with("nope", jwks_url: jwks_url).and_return(nil)

      expect { verifier.verify(rs256_token({sub: "user_123"}, header: {kid: "nope"})) }
        .to raise_error(Clowk::InvalidTokenError, /unknown signing key/)
    end

    it "rejects a token with no kid header" do
      expect { verifier.verify(rs256_token({sub: "user_123"}, header: {})) }
        .to raise_error(Clowk::InvalidTokenError, /missing kid/)
    end

    # Under RS256 every consumer trusts the same public key, so this is the only
    # thing standing between app A's token and app B's API.
    it "rejects a token minted for another audience" do
      token = rs256_token({sub: "user_123", aud: "pk_test_someone_else"})

      expect { verifier.verify(token) }.to raise_error(Clowk::InvalidTokenError)
    end

    it "skips audience verification when audience is nil" do
      verifier = described_class.new(secret_key: secret_key, issuer: issuer, audience: nil, jwks_url: jwks_url)

      expect(verifier.verify(rs256_token({sub: "user_123", aud: "anyone"}))[:sub]).to eq("user_123")
    end

    it "still enforces issuer" do
      expect { verifier.verify(rs256_token({sub: "user_123", iss: "somewhere_else"})) }
        .to raise_error(Clowk::InvalidTokenError, /Invalid issuer/)
    end

    it "still enforces expiry" do
      expect { verifier.verify(rs256_token({sub: "user_123", exp: Time.now.to_i - 60})) }
        .to raise_error(Clowk::InvalidTokenError, /expired/)
    end

    # HS256 tokens predating the migration carry no `aud`; enforcing audience on
    # that path would reject them while they are still valid.
    it "does not require an audience on legacy HS256 tokens" do
      legacy = encode_token({sub: "user_123", iss: issuer, exp: Time.now.to_i + 3600})

      expect(verifier.verify(legacy)[:sub]).to eq("user_123")
    end
  end
end
