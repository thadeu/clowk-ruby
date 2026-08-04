# frozen_string_literal: true

# Exercised through a real ActionController::API rather than a dummy class, so
# the app under test behaves the way Rails actually behaves rather than the way
# the double was written to.
RSpec.describe "API-only controller" do
  def get_api(headers: {})
    session = integration_session
    session.get "/api/me", headers: headers

    session.response
  end

  describe "unauthenticated" do
    # The bug this covers: `request.session` returns a working Session object
    # even with no session middleware, so inferring "browser" from its presence
    # answered every API call with a redirect to a sign-in page.
    it "returns 401 without an Accept header" do
      response = get_api

      expect(response.status).to eq(401)
      expect(JSON.parse(response.body)["error"]).to eq("Unauthorized")
    end

    it "returns 401 with an explicit JSON Accept header" do
      response = get_api(headers: {"Accept" => "application/json"})

      expect(response.status).to eq(401)
    end

    it "returns 401 for an HTML Accept header too" do
      response = get_api(headers: {"Accept" => "text/html"})

      expect(response.status).to eq(401)
    end

    it "never redirects" do
      expect(get_api.status).not_to eq(302)
    end
  end

  describe "authenticated" do
    it "authenticates from a bearer token" do
      response = get_api(headers: {"Authorization" => "Bearer #{issued_token}"})

      expect(response.status).to eq(200)
      expect(JSON.parse(response.body)).to include("sub" => "user_123")
    end

    # A bearer request has no browser to hold a cookie and no session to write
    # to; sending one back is noise at best.
    it "sets no cookie" do
      response = get_api(headers: {"Authorization" => "Bearer #{issued_token}"})

      expect(response.headers["Set-Cookie"]).to be_blank
    end

    it "rejects a malformed token" do
      expect(get_api(headers: {"Authorization" => "Bearer not.a.jwt"}).status).to eq(401)
    end
  end
end
