# frozen_string_literal: true

require "cgi"
require "uri"

RSpec.describe "Clowk engine flow" do
  it "redirects sign_in to the remote instance URL and embeds callback state" do
    session = integration_session

    session.get "/clowk/sign_in", params: { return_to: "/dashboard" }

    expect(session.response.status).to eq(302)

    remote_url = URI(session.response.location)
    expect(remote_url.to_s).to start_with("https://acme.clowk.dev/sign-in")

    redirect_uri = URI(CGI.unescape(CGI.parse(remote_url.query)["redirect_uri"].first))
    expect(redirect_uri.path).to eq("/clowk/oauth/callback")
    expect(CGI.parse(redirect_uri.query)).to include("state")
  end

  it "stores the authenticated session and redirects to the original internal path" do
    session = integration_session

    session.get "/clowk/sign_in", params: { return_to: "/dashboard" }

    remote_url = URI(session.response.location)
    redirect_uri = URI(CGI.unescape(CGI.parse(remote_url.query)["redirect_uri"].first))
    state = CGI.parse(redirect_uri.query)["state"].first

    session.get "/clowk/oauth/callback", params: { token: issued_token, state: state }

    expect(session.response.status).to eq(302)
    expect(session.response.location).to eq("http://www.example.com/dashboard")
    expect(Array(session.response.headers["Set-Cookie"]).join("\n")).to include("clowk_token=")
  end

  it "rejects callbacks with an invalid state" do
    session = integration_session

    session.get "/clowk/sign_in", params: { return_to: "/dashboard" }
    session.get "/clowk/oauth/callback", params: { token: issued_token, state: "invalid" }

    expect(session.response.status).to eq(302)
    expect(session.response.location).to eq("http://www.example.com/after_sign_out")
  end

  it "falls back to the default path when return_to is external" do
    session = integration_session

    session.get "/clowk/sign_in", params: { return_to: "https://evil.com/phish" }

    remote_url = URI(session.response.location)
    redirect_uri = URI(CGI.unescape(CGI.parse(remote_url.query)["redirect_uri"].first))
    state = CGI.parse(redirect_uri.query)["state"].first

    session.get "/clowk/oauth/callback", params: { token: issued_token, state: state }

    expect(session.response.status).to eq(302)
    expect(session.response.location).to eq("http://www.example.com/after_sign_in")
  end

  it "signs out and redirects to the configured after_sign_out path" do
    session = integration_session

    session.get "/clowk/sign_in", params: { return_to: "/dashboard" }
    remote_url = URI(session.response.location)
    redirect_uri = URI(CGI.unescape(CGI.parse(remote_url.query)["redirect_uri"].first))
    state = CGI.parse(redirect_uri.query)["state"].first
    session.get "/clowk/oauth/callback", params: { token: issued_token, state: state }

    session.get "/clowk/sign_out"

    expect(session.response.status).to eq(302)
    expect(session.response.location).to eq("http://www.example.com/after_sign_out")
  end
end