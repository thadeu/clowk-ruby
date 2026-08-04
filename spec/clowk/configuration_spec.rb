# frozen_string_literal: true

RSpec.describe Clowk::Configuration do
  subject(:configuration) { described_class.new }

  it "defaults the app_base_url to the public app" do
    expect(configuration.app_base_url).to eq("https://app.clowk.in")
  end

  it "defaults the callback_path to the oauth callback route" do
    expect(configuration.callback_path).to eq("/clowk/oauth/callback")
  end

  it "defaults the http timeouts and retries" do
    expect(configuration.http_logger).to be_nil
    expect(configuration.http_open_timeout).to eq(5)
    expect(configuration.http_read_timeout).to eq(10)
    expect(configuration.http_write_timeout).to eq(10)
    expect(configuration.http_retry_attempts).to eq(2)
    expect(configuration.http_retry_interval).to eq(0.05)
  end

  it "defaults the prefix_by to clowk" do
    expect(configuration.prefix_by).to eq(:clowk)
  end

  it "allows overriding the prefix_by" do
    configuration.prefix_by = :member

    expect(configuration.prefix_by).to eq(:member)
  end

  describe "#audience" do
    # Under RS256 every consumer trusts the same public key, so `aud` is the
    # only thing keeping one app's token out of another's API. Defaulting it to
    # the publishable key is what makes that check on by default instead of
    # something you have to know to switch on.
    it "defaults to the publishable key" do
      configuration.publishable_key = "pk_test_contagorda"

      expect(configuration.audience).to eq("pk_test_contagorda")
    end

    it "allows an explicit override" do
      configuration.publishable_key = "pk_test_contagorda"
      configuration.audience = "something-else"

      expect(configuration.audience).to eq("something-else")
    end

    it "can be switched off explicitly" do
      configuration.publishable_key = "pk_test_contagorda"
      configuration.audience = false

      expect(configuration.audience).to be(false)
    end

    it "is nil when no publishable key is configured" do
      expect(configuration.audience).to be_nil
    end
  end

  describe "#jwks_url" do
    it "is nil by default so the auth domain is used" do
      expect(configuration.jwks_url).to be_nil
    end

    it "is overridable" do
      configuration.jwks_url = "https://auth.example.com/.well-known/jwks.json"

      expect(configuration.jwks_url).to eq("https://auth.example.com/.well-known/jwks.json")
    end
  end

  describe "#session_status_cache" do
    it "is overridable" do
      store = ActiveSupport::Cache::MemoryStore.new
      configuration.session_status_cache = store

      expect(configuration.session_status_cache).to be(store)
    end

    it "can be switched off so status is checked every time" do
      configuration.session_status_cache = nil

      expect(configuration.session_status_cache).to be_nil
    end
  end
end
