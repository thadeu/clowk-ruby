# frozen_string_literal: true

require "base64"
require "json"
require "openssl"

RSpec.describe Clowk::Jwks do
  let(:jwks_url) { "https://auth.example.com/.well-known/jwks.json" }
  let(:rsa) { OpenSSL::PKey::RSA.generate(2048) }
  let(:kid) { "key-one" }

  def b64(bytes)
    Base64.urlsafe_encode64(bytes, padding: false)
  end

  def jwk_for(key, kid:)
    {
      "kty" => "RSA",
      "use" => "sig",
      "alg" => "RS256",
      "kid" => kid,
      "n" => b64(key.n.to_s(2)),
      "e" => b64(key.e.to_s(2))
    }
  end

  def response_for(*jwks, success: true)
    body = JSON.generate({keys: jwks})

    Clowk::Http::Response.new(
      status: success ? 200 : 500,
      body: body,
      body_parsed: JSON.parse(body),
      headers: {},
      success: success
    )
  end

  before { described_class.clear_cache! }

  after { described_class.clear_cache! }

  describe ".key_for" do
    it "fetches and rebuilds the public key" do
      allow(Clowk::Http).to receive(:get).and_return(response_for(jwk_for(rsa, kid: kid)))

      key = described_class.key_for(kid, jwks_url: jwks_url)

      expect(key).to be_a(OpenSSL::PKey::RSA)
      expect(key.n).to eq(rsa.n)
      expect(key.e).to eq(rsa.e)
    end

    it "never rebuilds a private key" do
      allow(Clowk::Http).to receive(:get).and_return(response_for(jwk_for(rsa, kid: kid)))

      expect(described_class.key_for(kid, jwks_url: jwks_url).private?).to be(false)
    end

    # Verifying a token must not cost a round trip.
    it "serves later lookups from cache" do
      allow(Clowk::Http).to receive(:get).once.and_return(response_for(jwk_for(rsa, kid: kid)))

      3.times { described_class.key_for(kid, jwks_url: jwks_url) }

      expect(Clowk::Http).to have_received(:get).once
    end

    it "returns every key in the set" do
      other = OpenSSL::PKey::RSA.generate(2048)
      allow(Clowk::Http).to receive(:get)
        .and_return(response_for(jwk_for(rsa, kid: kid), jwk_for(other, kid: "key-two")))

      expect(described_class.key_for(kid, jwks_url: jwks_url).n).to eq(rsa.n)
      expect(described_class.key_for("key-two", jwks_url: jwks_url).n).to eq(other.n)
    end

    # This is what makes rotation invisible: the successor appears mid-cache and
    # one refetch picks it up instead of failing until the TTL expires.
    it "refetches once when it sees an unknown kid" do
      rotated = OpenSSL::PKey::RSA.generate(2048)

      allow(Clowk::Http).to receive(:get).and_return(
        response_for(jwk_for(rsa, kid: kid)),
        response_for(jwk_for(rsa, kid: kid), jwk_for(rotated, kid: "key-two"))
      )

      described_class.key_for(kid, jwks_url: jwks_url)

      expect(described_class.key_for("key-two", jwks_url: jwks_url).n).to eq(rotated.n)
      expect(Clowk::Http).to have_received(:get).twice
    end

    it "returns nil for a kid that is genuinely absent" do
      allow(Clowk::Http).to receive(:get).and_return(response_for(jwk_for(rsa, kid: kid)))

      expect(described_class.key_for("nope", jwks_url: jwks_url)).to be_nil
    end

    # A forged kid must not turn one bad token into a stampede on the auth
    # server. The first miss is allowed to check for a rotation; the rest are
    # throttled until the cooldown passes.
    it "does not refetch on every unknown kid" do
      allow(Clowk::Http).to receive(:get).and_return(response_for(jwk_for(rsa, kid: kid)))
      described_class.key_for(kid, jwks_url: jwks_url)

      20.times { |i| described_class.key_for("forged-#{i}", jwks_url: jwks_url) }

      expect(Clowk::Http).to have_received(:get).twice
    end

    it "raises when the endpoint fails" do
      allow(Clowk::Http).to receive(:get).and_return(response_for(success: false))

      expect { described_class.key_for(kid, jwks_url: jwks_url) }
        .to raise_error(Clowk::InvalidTokenError, /could not fetch JWKS/)
    end

    it "raises on a malformed document" do
      malformed = Clowk::Http::Response.new(
        status: 200, body: "not json", body_parsed: nil, headers: {}, success: true
      )
      allow(Clowk::Http).to receive(:get).and_return(malformed)

      expect { described_class.key_for(kid, jwks_url: jwks_url) }
        .to raise_error(Clowk::InvalidTokenError, /malformed JWKS/)
    end

    it "ignores non-RSA entries" do
      allow(Clowk::Http).to receive(:get)
        .and_return(response_for({"kty" => "EC", "kid" => "ec-key"}, jwk_for(rsa, kid: kid)))

      expect(described_class.key_for("ec-key", jwks_url: jwks_url)).to be_nil
      expect(described_class.key_for(kid, jwks_url: jwks_url)).to be_a(OpenSSL::PKey::RSA)
    end
  end

  describe ".default_url" do
    it "derives the well-known path from the configured subdomain" do
      allow(Clowk.config).to receive(:subdomain_url).and_return("https://auth.example.com/")

      expect(described_class.default_url).to eq(jwks_url)
    end

    it "explains what is missing when nothing is configured" do
      allow(Clowk.config).to receive(:subdomain_url).and_return(nil)
      allow(Clowk::Subdomain).to receive(:resolve_url!).and_raise(Clowk::ConfigurationError)

      expect { described_class.default_url }
        .to raise_error(Clowk::ConfigurationError, /jwks_url, subdomain_url or publishable_key/)
    end
  end
end
