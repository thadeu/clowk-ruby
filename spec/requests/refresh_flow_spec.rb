# frozen_string_literal: true

require "cgi"
require "uri"

RSpec.describe "Session refresh flow" do
  let(:publishable_key) { "pk_test_refresh" }
  let(:lifetime) { 30 * 24 * 60 * 60 }

  let(:pair) do
    {
      access_token: issued_token(aud: publishable_key, email: "fresh@example.com"),
      refresh_token: "clk_rt_second",
      expires_in: 3600,
      refresh_expires_in: lifetime,
      session_id: "clk_session_1"
    }
  end

  before do
    Clowk.configure do |config|
      config.publishable_key = publishable_key
      config.session_status_cache = ActiveSupport::Cache::MemoryStore.new
    end

    allow(Clowk::Subdomain).to receive(:resolve_url!).and_return("https://acme.clowk.dev")
  end

  def set_cookie_line(response, key)
    Array(response.headers["Set-Cookie"]).join("\n").lines.find { |line| line.start_with?("#{key}=") }
  end

  def cookie_expiry(response, key)
    Time.httpdate(set_cookie_line(response, key)[/expires=([^;]+)/i, 1])
  end

  def sign_in(session, token)
    session.get "/clowk/sign_in", params: {return_to: "/private"}

    remote_url = URI(session.response.location)
    redirect_uri = URI(CGI.unescape(CGI.parse(remote_url.query)["redirect_uri"].first))
    state = CGI.parse(redirect_uri.query)["state"].first

    session.get "/clowk/oauth/callback", params: {token: token, state: state}
  end

  describe "sign-in callback" do
    it "trades the sign-in token for a pair kept for the session lifetime" do
      allow_any_instance_of(Clowk::SDK::SessionToken).to receive(:exchange).and_return(pair)

      session = integration_session

      sign_in(session, issued_token(aud: publishable_key, session_id: "clk_session_1"))

      expect(session.response.location).to eq("http://www.example.com/private")
      expect(cookie_expiry(session.response, "clowk_token")).to be_within(1.minute).of(Time.now + lifetime)
      expect(cookie_expiry(session.response, "clowk_refresh_token")).to be_within(1.minute).of(Time.now + lifetime)
    end

    it "keeps the sign-in token when the exchange is refused" do
      allow_any_instance_of(Clowk::SDK::SessionToken)
        .to receive(:exchange).and_raise(Clowk::InvalidTokenError, "Session not found")

      session = integration_session

      sign_in(session, issued_token(aud: publishable_key))

      expect(session.response.location).to eq("http://www.example.com/private")
      expect(set_cookie_line(session.response, "clowk_token")).to include("expires=")
      expect(set_cookie_line(session.response, "clowk_refresh_token")).to be_nil
    end

    it "skips the exchange without a publishable key" do
      Clowk.configure { |config| config.publishable_key = nil }

      expect_any_instance_of(Clowk::SDK::SessionToken).not_to receive(:exchange)

      session = integration_session

      sign_in(session, issued_token)

      expect(session.response.location).to eq("http://www.example.com/private")
    end
  end

  # The PWA case: the app was closed for hours, the host app's session cookie
  # is gone, and the access token has expired. The refresh cookie must sign
  # the user back in without a trip to the sign-in page.
  describe "returning with an expired access token" do
    let(:expired_token) { issued_token(aud: publishable_key, exp: 2.hours.ago.to_i) }

    it "renews the token and serves the page" do
      allow_any_instance_of(Clowk::SDK::SessionToken).to receive(:refresh)
        .with(refresh_token: "clk_rt_first").and_return(pair)

      session = integration_session
      session.cookies["clowk_token"] = expired_token
      session.cookies["clowk_refresh_token"] = "clk_rt_first"

      session.get "/private"

      expect(session.response.status).to eq(200)
      expect(session.response.body).to eq("fresh@example.com #{pair[:access_token]}")
      expect(cookie_expiry(session.response, "clowk_refresh_token")).to be_within(1.minute).of(Time.now + lifetime)
    end

    it "renews when only the refresh cookie is left" do
      allow_any_instance_of(Clowk::SDK::SessionToken).to receive(:refresh).and_return(pair)

      session = integration_session
      session.cookies["clowk_refresh_token"] = "clk_rt_first"

      session.get "/private"

      expect(session.response.status).to eq(200)
    end

    it "signs out when Clowk refuses the refresh" do
      allow_any_instance_of(Clowk::SDK::SessionToken)
        .to receive(:refresh).and_raise(Clowk::InvalidTokenError, "Invalid refresh token")

      session = integration_session
      session.cookies["clowk_token"] = expired_token
      session.cookies["clowk_refresh_token"] = "clk_rt_first"

      session.get "/private"

      expect(session.response.status).to eq(302)
      expect(session.response.location).to include("/clowk/sign_in")
      expect(set_cookie_line(session.response, "clowk_refresh_token")).to include("max-age=0").or include("expires=Thu, 01 Jan 1970")
    end

    it "keeps the cookies when Clowk cannot be reached" do
      allow_any_instance_of(Clowk::SDK::SessionToken).to receive(:refresh).and_raise(Errno::ECONNREFUSED)

      session = integration_session
      session.cookies["clowk_token"] = expired_token
      session.cookies["clowk_refresh_token"] = "clk_rt_first"

      session.get "/private"

      expect(session.response.status).to eq(302)
      expect(set_cookie_line(session.response, "clowk_refresh_token")).to be_nil
    end

    it "does not refresh a token that is still valid" do
      expect_any_instance_of(Clowk::SDK::SessionToken).not_to receive(:refresh)

      session = integration_session
      session.cookies["clowk_token"] = issued_token(aud: publishable_key)
      session.cookies["clowk_refresh_token"] = "clk_rt_first"

      session.get "/private"

      expect(session.response.status).to eq(200)
    end
  end

  describe "sign out" do
    it "revokes the session on Clowk and drops both cookies" do
      allow_any_instance_of(Clowk::SDK::SessionToken).to receive(:exchange).and_return(pair)
      expect_any_instance_of(Clowk::SDK::SessionToken).to receive(:revoke).with(refresh_token: "clk_rt_second")

      session = integration_session

      sign_in(session, issued_token(aud: publishable_key, session_id: "clk_session_1"))

      session.get "/clowk/sign_out"

      expect(set_cookie_line(session.response, "clowk_refresh_token")).to be_present
      expect(session.cookies["clowk_refresh_token"]).to be_blank
    end
  end
end
