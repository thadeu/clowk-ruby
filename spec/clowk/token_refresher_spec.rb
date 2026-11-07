# frozen_string_literal: true

RSpec.describe Clowk::TokenRefresher do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:session_tokens) { instance_double(Clowk::SDK::SessionToken) }
  let(:client) { double("Clowk::SDK::Client", session_tokens: session_tokens) }
  let(:pair) { {access_token: "at_2", refresh_token: "rt_2", refresh_expires_in: 600} }

  subject(:refresher) { described_class.new(cache: cache, client: client) }

  before { Clowk.configure { |config| config.publishable_key = "pk_test" } }

  describe "#refresh" do
    it "rotates the refresh token" do
      allow(session_tokens).to receive(:refresh).with(refresh_token: "rt_1").and_return(pair)

      expect(refresher.refresh("rt_1")).to eq(pair)
    end

    # Rotation lets a refresh token work once. Two requests with the same one
    # must share one rotation, not spend it twice.
    it "shares one rotation between requests with the same token" do
      allow(session_tokens).to receive(:refresh).once.and_return(pair)

      first = refresher.refresh("rt_1")
      second = described_class.new(cache: cache, client: client).refresh("rt_1")

      expect(second).to eq(first)
      expect(session_tokens).to have_received(:refresh).once
    end

    it "waits for a rotation in flight and uses its result" do
      cache.write("clowk:refresh:lock:#{Digest::SHA256.hexdigest("rt_1")}", 1)

      Thread.new do
        sleep 0.1
        cache.write("clowk:refresh:result:#{Digest::SHA256.hexdigest("rt_1")}", pair)
      end

      expect(refresher.refresh("rt_1")).to eq(pair)
    end

    it "tells the waiting requests when the rotation was refused" do
      allow(session_tokens).to receive(:refresh).and_raise(Clowk::InvalidTokenError, "Invalid refresh token")

      expect { refresher.refresh("rt_1") }.to raise_error(Clowk::InvalidTokenError)
      expect { described_class.new(cache: cache, client: client).refresh("rt_1") }
        .to raise_error(Clowk::InvalidTokenError, /refused/)

      expect(session_tokens).to have_received(:refresh).once
    end

    it "releases the lock when the broker cannot be reached" do
      allow(session_tokens).to receive(:refresh).and_raise(Errno::ECONNREFUSED)

      expect { refresher.refresh("rt_1") }.to raise_error(Errno::ECONNREFUSED)
      expect(cache.read("clowk:refresh:lock:#{Digest::SHA256.hexdigest("rt_1")}")).to be_nil
    end

    it "works without a cache" do
      allow(session_tokens).to receive(:refresh).and_return(pair)

      expect(described_class.new(cache: nil, client: client).refresh("rt_1")).to eq(pair)
    end
  end

  describe "#exchange" do
    it "returns nil without a publishable key" do
      Clowk.configure { |config| config.publishable_key = nil }

      expect(refresher.exchange("token")).to be_nil
    end

    it "trades the sign-in token for a pair" do
      allow(session_tokens).to receive(:exchange).with(token: "token").and_return(pair)

      expect(refresher.exchange("token")).to eq(pair)
    end
  end

  describe "#revoke" do
    it "never fails a sign-out" do
      allow(session_tokens).to receive(:revoke).and_raise(Errno::ECONNREFUSED)

      expect(refresher.revoke("rt_1")).to be_nil
    end

    it "does nothing without a refresh token" do
      expect(session_tokens).not_to receive(:revoke)

      refresher.revoke(nil)
    end
  end
end
