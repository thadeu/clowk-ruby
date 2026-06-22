# frozen_string_literal: true

RSpec.describe Clowk::SDK::Token do
  subject(:resource) { described_class.new(http_client) }

  let(:http_client) { instance_double(Clowk::Http) }

  describe ".resource_path" do
    it "is tokens" do
      expect(described_class.resource_path).to eq("tokens")
    end
  end

  describe "#verify" do
    it "calls POST /tokens/verify with the token" do
      response = Clowk::Http::Response.new(
        status: 200,
        body: '{"ok":true}',
        body_parsed: {"ok" => true},
        headers: {},
        success: true
      )

      allow(http_client).to receive(:post)
        .with("tokens/verify", {token: "jwt_abc"})
        .and_return(response)

      expect(resource.verify(token: "jwt_abc")).to eq(response)
    end
  end

  describe "#verify_with_session" do
    it "returns the symbolized data on success" do
      response = Clowk::Http::Response.new(
        status: 200,
        body: '{"data":{"session":{"status":"active"}}}',
        body_parsed: {"data" => {"session" => {"status" => "active"}}},
        headers: {},
        success: true
      )

      allow(http_client).to receive(:post)
        .with("tokens/verify", {token: "jwt_abc"})
        .and_return(response)

      result = resource.verify_with_session(token: "jwt_abc")

      expect(result).to eq(session: {status: "active"})
    end

    it "raises InvalidTokenError with the API error message on failure" do
      response = Clowk::Http::Response.new(
        status: 401,
        body: '{"error":"token expired"}',
        body_parsed: {"error" => "token expired"},
        headers: {},
        success: false
      )

      allow(http_client).to receive(:post)
        .with("tokens/verify", {token: "expired"})
        .and_return(response)

      expect { resource.verify_with_session(token: "expired") }
        .to raise_error(Clowk::InvalidTokenError, "token expired")
    end

    it "raises InvalidTokenError with a fallback message when no error is given" do
      response = Clowk::Http::Response.new(
        status: 500,
        body: "",
        body_parsed: nil,
        headers: {},
        success: false
      )

      allow(http_client).to receive(:post)
        .with("tokens/verify", {token: "broken"})
        .and_return(response)

      expect { resource.verify_with_session(token: "broken") }
        .to raise_error(Clowk::InvalidTokenError, "token verification failed")
    end
  end
end
