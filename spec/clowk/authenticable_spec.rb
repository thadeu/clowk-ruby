# frozen_string_literal: true

RSpec.describe Clowk::Authenticable do
  let(:payload) do
    {
      "sub" => "user_123",
      "email" => "user@example.com",
      "name" => "Jane Doe"
    }
  end

  let(:request_format) { instance_double("RequestFormat", json?: false) }

  let(:request) do
    instance_double(
      "Request",
      format: request_format,
      fullpath: "/dashboard",
      params: {},
      authorization: nil
    )
  end

  let(:dummy_class) do
    Class.new do
      include Clowk::Helpers::UrlHelpers
      include Clowk::Authenticable

      attr_reader :session, :cookies, :redirect_target

      def initialize(request:, session_data: nil)
        @session = {}
        @session[Clowk.config.session_key] = session_data if session_data
        @cookies = {}
        @request = request
      end

      attr_reader :request

      def redirect_to(target)
        @redirect_target = target
      end
    end
  end

  it "exposes default clowk helper names" do
    instance = dummy_class.new(session_data: {user: payload}, request: request)

    expect(instance).to respond_to(:current_clowk, :authenticate_clowk!, :clowk_signed_in?)
    expect(instance.current_clowk).to be_a(Clowk::Current)
    expect(instance.current_clowk.email).to eq("user@example.com")
    expect(instance.clowk_signed_in?).to be(true)
  end

  it "generates helper names from the configured prefix_by" do
    Clowk.configure do |config|
      config.prefix_by = :member
    end

    custom_class = Class.new do
      include Clowk::Helpers::UrlHelpers
      include Clowk::Authenticable

      attr_reader :session, :cookies, :redirect_target

      def initialize(request:, session_data: nil)
        @session = {}
        @session[Clowk.config.session_key] = session_data if session_data
        @cookies = {}
        @request = request
      end

      attr_reader :request

      def redirect_to(target)
        @redirect_target = target
      end
    end

    instance = custom_class.new(session_data: {user: payload}, request: request)

    expect(instance).to respond_to(:current_member, :authenticate_member!, :member_signed_in?)
    expect(instance.current_member).to be_a(Clowk::Current)
    expect(instance.member_signed_in?).to be(true)
  end

  it "redirects unauthenticated requests to the mounted sign in path" do
    instance = dummy_class.new(request: request)

    instance.authenticate_clowk!

    expect(instance.redirect_target).to eq("/clowk/sign_in?return_to=%2Fdashboard")
  end

  it "redirects to sign in (instead of raising) when session verification fails" do
    sdk_client = double("Clowk::SDK::Client")
    tokens = instance_double(Clowk::SDK::Token)

    allow(Clowk::SDK::Client).to receive(:new).and_return(sdk_client)
    allow(sdk_client).to receive(:tokens).and_return(tokens)
    allow(tokens).to receive(:verify_with_session)
      .and_raise(Clowk::InvalidTokenError, "token expired")

    instance = dummy_class.new(
      session_data: {user: payload.merge("session_id" => "clk_session_abc")},
      request: request
    )

    expect { instance.clowk_enforce_session! }.not_to raise_error
    expect(instance.redirect_target).to eq("/clowk/sign_in?return_to=%2Fdashboard")
  end

  describe "token sources" do
    let(:valid_token) do
      JWT.encode(
        payload.merge(iss: Clowk.config.issuer, exp: 1.hour.from_now.to_i),
        Clowk.config.secret_key,
        Clowk::JwtVerifier::ALGORITHM
      )
    end

    # A token in a query string must never establish a session: it would sign the
    # visitor in on any path without passing the callback's state check, and stay
    # replayable wherever the URL got logged.
    it "refuses to sign in from a token in the query string" do
      request = instance_double(
        "Request", format: request_format, fullpath: "/dashboard",
        params: {"token" => valid_token}, authorization: nil
      )

      instance = dummy_class.new(request: request)

      expect(instance.clowk_signed_in?).to be(false)
      expect(instance.current_clowk).to be_nil
    end

    it "still signs in from a bearer header" do
      request = instance_double(
        "Request", format: request_format, fullpath: "/dashboard",
        params: {}, authorization: "Bearer #{valid_token}", ssl?: false
      )

      instance = dummy_class.new(request: request)

      expect(instance.clowk_signed_in?).to be(true)
      expect(instance.current_clowk.email).to eq("user@example.com")
    end
  end

  describe "session status caching" do
    let(:cached) { {"status" => "active", "session_id" => "clk_session_abc"} }

    # No session_id in the payload means resolve_session_status bails before any
    # network call — so whatever comes back came from the cache, or nowhere.
    def instance_with(session_status_extras)
      dummy_class.new(
        session_data: {:user => payload, "session_status" => cached}.merge(session_status_extras),
        request: request
      )
    end

    it "trusts a cached status inside the TTL" do
      Clowk.configure { |config| config.session_status_ttl = 300 }

      instance = instance_with("session_status_checked_at" => Time.now.to_i)

      expect(instance.clowk_session_status).to include(status: "active")
    end

    it "discards a cached status once the TTL has passed" do
      Clowk.configure { |config| config.session_status_ttl = 300 }

      instance = instance_with("session_status_checked_at" => Time.now.to_i - 600)

      expect(instance.clowk_session_status).to be_nil
    end

    # The shape written before TTLs existed. Without this, a status cached once
    # is trusted for the life of the Rails session and enforcement never runs.
    it "discards a cached status that carries no timestamp" do
      instance = instance_with({})

      expect(instance.clowk_session_status).to be_nil
    end

    it "always re-checks when the TTL is zero" do
      Clowk.configure { |config| config.session_status_ttl = 0 }

      instance = instance_with("session_status_checked_at" => Time.now.to_i)

      expect(instance.clowk_session_status).to be_nil
    end
  end

  it "generates a sign-out helper matching the configured prefix_by" do
    Clowk.configure { |config| config.prefix_by = :clowk_user }

    custom_class = Class.new do
      include Clowk::Helpers::UrlHelpers
      include Clowk::Authenticable

      attr_reader :session, :cookies

      def initialize
        @session = {}
        @cookies = {}
      end
    end

    expect(custom_class.new).to respond_to(:clowk_user_sign_out!)
  end

  # An API-only Rails app has neither session nor cookie middleware. Touching
  # either raises, which is what the gem used to do on every successful bearer
  # verification.
  describe "API-only controllers" do
    let(:api_class) do
      Class.new do
        include Clowk::Helpers::UrlHelpers
        include Clowk::Authenticable

        attr_reader :request, :rendered, :redirect_target

        def initialize(request:)
          @request = request
        end

        def session
          raise ActionDispatch::Request::Session::DisabledSessionError, "disabled"
        end

        def cookies
          raise "no cookie middleware"
        end

        def render(options)
          @rendered = options
        end

        def redirect_to(target)
          @redirect_target = target
        end
      end
    end

    let(:valid_token) do
      JWT.encode(
        payload.merge(iss: Clowk.config.issuer, exp: 1.hour.from_now.to_i),
        Clowk.config.secret_key,
        Clowk::JwtVerifier::LEGACY_ALGORITHM
      )
    end

    let(:bearer_request) do
      instance_double(
        "Request", format: request_format, fullpath: "/api/v1/me",
        params: {}, authorization: "Bearer #{valid_token}", ssl?: true
      )
    end

    it "authenticates from a bearer header without a session" do
      instance = api_class.new(request: bearer_request)

      expect(instance.clowk_signed_in?).to be(true)
      expect(instance.current_clowk.email).to eq("user@example.com")
    end

    # The old behaviour wrote a Set-Cookie on every bearer request: useless to a
    # mobile client and a per-request session write in a stateless API.
    it "does not try to persist a session or cookie" do
      instance = api_class.new(request: bearer_request)

      expect { instance.clowk_authenticate! }.not_to raise_error
    end

    # Without an Accept header the format is not json, and the old code answered
    # a failed API call with a 302 to a sign-in page the caller cannot use.
    it "answers 401 JSON even when the format is not json" do
      unauthenticated = instance_double(
        "Request", format: request_format, fullpath: "/api/v1/me",
        params: {}, authorization: nil
      )

      instance = api_class.new(request: unauthenticated)
      instance.clowk_authenticate!

      expect(instance.rendered).to include(status: :unauthorized)
      expect(instance.redirect_target).to be_nil
    end

    it "signs out without touching the missing stores" do
      instance = api_class.new(request: bearer_request)

      expect { instance.clowk_sign_out! }.not_to raise_error
    end

    describe "session status caching" do
      let(:cache) { ActiveSupport::Cache::MemoryStore.new }

      before do
        Clowk.configure do |config|
          config.session_status_cache = cache
          config.session_status_ttl = 300
        end
      end

      after { Clowk.configure { |config| config.session_status_cache = nil } }

      # Without an external store every authenticated request would pay a round
      # trip to Clowk, because there is no Rails session to cache into.
      it "reads a cached status from the configured store" do
        instance = api_class.new(request: bearer_request)
        key = "clowk:session_status:#{Digest::SHA256.hexdigest(valid_token)}"
        cache.write(key, {"status" => "active", "session_id" => "clk_session_abc"})

        expect(instance.clowk_session_status).to include(status: "active")
      end

      it "keys the cache by digest so the raw token never lands in a cache key" do
        instance = api_class.new(request: bearer_request)
        cache.write(
          "clowk:session_status:#{Digest::SHA256.hexdigest(valid_token)}",
          {"status" => "active"}
        )

        instance.clowk_session_status

        expect(cache.instance_variable_get(:@data).keys.join).not_to include(valid_token)
      end
    end
  end
end
