# frozen_string_literal: true

RSpec.describe Clowk::SDK::SessionToken do
  let(:client) { instance_double(Clowk::SDK::Client) }

  subject(:resource) { described_class.new(client) }

  def response(status:, body:)
    Clowk::Http::Response.new(status: status, body: body.to_json, body_parsed: body, headers: {}, success: status < 400)
  end

  it "returns the pair with symbol keys" do
    allow(client).to receive(:post).with("sessions/refresh", {refresh_token: "rt_1"})
      .and_return(response(status: 200, body: {"access_token" => "at", "refresh_token" => "rt_2", "refresh_expires_in" => 60}))

    expect(resource.refresh(refresh_token: "rt_1")).to include(access_token: "at", refresh_token: "rt_2", refresh_expires_in: 60)
  end

  it "raises when Clowk refuses" do
    allow(client).to receive(:post).and_return(response(status: 401, body: {"error" => "Invalid refresh token"}))

    expect { resource.refresh(refresh_token: "rt_1") }.to raise_error(Clowk::InvalidTokenError, "Invalid refresh token")
  end

  it "posts the sign-in token to the exchange endpoint" do
    allow(client).to receive(:post).with("sessions/exchange", {token: "jwt"})
      .and_return(response(status: 200, body: {"access_token" => "at"}))

    expect(resource.exchange(token: "jwt")).to include(access_token: "at")
  end

  it "is reachable from the client" do
    expect(Clowk::SDK::Client.new(secret_key: nil, publishable_key: "pk").session_tokens).to be_a(described_class)
  end
end
