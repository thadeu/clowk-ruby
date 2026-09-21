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

    describe "writing a status back" do
      let(:status) { {"status" => "active", "session_id" => "clk_session_abc"} }

      def write!(instance)
        instance.send(:clowk_write_cached_session_status, status)
      end

      it "stores it in the session when a TTL allows caching" do
        Clowk.configure { |config| config.session_status_ttl = 300 }

        instance = dummy_class.new(session_data: {user: payload}, request: request)

        write!(instance)

        stored = instance.session[Clowk.config.session_key]

        expect(stored["session_status"]).to eq(status)
        expect(stored["session_status_checked_at"]).to be_within(2).of(Time.now.to_i)
      end

      # The bug behind a CookieOverflow. A TTL of zero says "never trust a
      # cached status", and the read side honours it — but the session branch
      # wrote one anyway, on every request, never read back, until the cookie
      # passed 4096 bytes and Rails refused the response.
      it "writes nothing to the session when the TTL is zero" do
        Clowk.configure { |config| config.session_status_ttl = 0 }

        instance = dummy_class.new(session_data: {user: payload}, request: request)
        before = instance.session[Clowk.config.session_key].dup

        write!(instance)

        expect(instance.session[Clowk.config.session_key]).to eq(before)
      end

      it "keeps the session small enough to survive a flash message" do
        Clowk.configure { |config| config.session_status_ttl = 0 }

        instance = dummy_class.new(session_data: {user: payload}, request: request)

        10.times { write!(instance) }

        expect(instance.session.to_s.bytesize).to be < 500
      end
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

      it "writes a freshly fetched status into the store" do
        sdk_client = double("Clowk::SDK::Client")
        tokens = double("Clowk::SDK::Token")
        allow(Clowk::SDK::Client).to receive(:new).and_return(sdk_client)
        allow(sdk_client).to receive(:tokens).and_return(tokens)
        allow(tokens).to receive(:verify_with_session)
          .and_return({session: {status: "active", session_id: "clk_session_abc"}})

        token_with_session = JWT.encode(
          payload.merge(iss: Clowk.config.issuer, session_id: "clk_session_abc", exp: 1.hour.from_now.to_i),
          Clowk.config.secret_key, Clowk::JwtVerifier::LEGACY_ALGORITHM
        )
        request = instance_double(
          "Request", format: request_format, fullpath: "/api/v1/me",
          params: {}, authorization: "Bearer #{token_with_session}", ssl?: true
        )

        api_class.new(request: request).clowk_session_status

        key = "clowk:session_status:#{Digest::SHA256.hexdigest(token_with_session)}"
        expect(cache.read(key)).to include(status: "active")
      end

      # Without a store there is nowhere to cache, but authentication must still
      # work — it just pays the round trip every time.
      it "still resolves status with caching switched off" do
        Clowk.configure { |config| config.session_status_cache = nil }

        sdk_client = double("Clowk::SDK::Client")
        tokens = double("Clowk::SDK::Token")
        allow(Clowk::SDK::Client).to receive(:new).and_return(sdk_client)
        allow(sdk_client).to receive(:tokens).and_return(tokens)
        allow(tokens).to receive(:verify_with_session)
          .and_return({session: {status: "active"}})

        token_with_session = JWT.encode(
          payload.merge(iss: Clowk.config.issuer, session_id: "clk_session_abc", exp: 1.hour.from_now.to_i),
          Clowk.config.secret_key, Clowk::JwtVerifier::LEGACY_ALGORITHM
        )
        request = instance_double(
          "Request", format: request_format, fullpath: "/api/v1/me",
          params: {}, authorization: "Bearer #{token_with_session}", ssl?: true
        )

        expect(api_class.new(request: request).clowk_session_status).to include(status: "active")
      end
    end

    # Regression: `nil.respond_to?(:to_h)` is true, so guarding on that alone
    # turned a missing store into an empty hash — truthy — and every caller that
    # branched on "is there a session?" silently took the session path.
    describe "missing session store" do
      it "reports no stored session rather than an empty hash" do
        instance = api_class.new(request: bearer_request)

        expect(instance.send(:stored_session)).to be_nil
      end

      it "reports the store itself as absent" do
        instance = api_class.new(request: bearer_request)

        expect(instance.send(:clowk_session_store)).to be_nil
        expect(instance.send(:clowk_cookie_jar)).to be_nil
      end
    end
  end
  it "names the fresh-session check for the configured prefix, like every other method" do
    Clowk.configure { |config| config.prefix_by = :clowk_user }

    scoped_class = Class.new do
      include Clowk::Helpers::UrlHelpers
      include Clowk::Authenticable

      attr_reader :session, :cookies

      def initialize(request:)
        @session = {}
        @cookies = {}
        @request = request
      end

      attr_reader :request
    end

    instance = scoped_class.new(request: request)

    expect(instance).to respond_to(:clowk_user_enforce_fresh_session!, :clowk_user_enforce_session!)
    expect(scoped_class).not_to respond_to(:clowk_require_fresh_session)
  end

  describe "token_store (0.9)" do
    before { Clowk.configure { |config| config.secret_key = "sk_test" } }

    let(:valid_token) do
      JWT.encode(
        payload.merge(iss: Clowk.config.issuer, exp: 1.hour.from_now.to_i),
        Clowk.config.secret_key,
        Clowk::JwtVerifier::ALGORITHM
      )
    end

    # The token comes off the REQUEST, the way it does in production: Clowk's
    # own cookie, read through the request's jar.
    let(:cookie_request) do
      instance_double(
        "Request", format: request_format, fullpath: "/dashboard",
        params: {}, authorization: nil, ssl?: true,
        cookie_jar: {Clowk.config.cookie_key => valid_token}
      )
    end

    def signed_in_with_cookie
      dummy_class.new(request: cookie_request)
    end

    def session_blob(instance)
      instance.session[Clowk.config.session_key]
    end

    it "mirrors the token into the session by default, as before 0.9" do
      instance = signed_in_with_cookie

      instance.send(:persist_clowk_session, valid_token, {"sub" => "user_123"})

      expect(session_blob(instance).keys).to include(:token, :user, :signed_in_at)
    end

    # The whole point. A Rails session lives in one 4096-byte cookie, and an
    # RS256 token is most of what one weighs — enough that a flash message on
    # top is what tips a browser into discarding the cookie whole.
    it "keeps the token out of the session under :cookie" do
      Clowk.configure { |config| config.token_store = :cookie }

      instance = signed_in_with_cookie

      instance.send(:persist_clowk_session, valid_token, {"sub" => "user_123"})

      expect(session_blob(instance).keys).to contain_exactly(:user, :signed_in_at)
    end

    it "still finds the token, from Clowk's own cookie" do
      Clowk.configure { |config| config.token_store = :cookie }

      instance = signed_in_with_cookie

      instance.send(:persist_clowk_session, valid_token, {"sub" => "user_123"})

      expect(instance.current_token).to eq(valid_token)
    end

    it "still knows who is signed in, from the claims the session keeps" do
      Clowk.configure { |config| config.token_store = :cookie }

      instance = signed_in_with_cookie

      expect(instance.clowk_signed_in?).to be(true)
      expect(instance.current_clowk.email).to eq("user@example.com")
    end

    # Sessions written before the switch keep the copy, and persist_clowk_session
    # does not run again while one stands — so without the prune an app would
    # shrink nothing until every person signed out.
    it "drops a copy left by a session written under :session" do
      Clowk.configure { |config| config.token_store = :cookie }

      instance = dummy_class.new(
        session_data: {"token" => valid_token, "user" => payload, "signed_in_at" => Time.now.to_i},
        request: cookie_request
      )

      instance.clowk_signed_in?

      expect(session_blob(instance).keys).not_to include("token")
      expect(session_blob(instance)["user"]).to eq(payload)
    end

    it "leaves that copy alone under :session" do
      instance = dummy_class.new(
        session_data: {"token" => valid_token, "user" => payload},
        request: cookie_request
      )

      instance.clowk_signed_in?

      expect(session_blob(instance)["token"]).to eq(valid_token)
    end

    it "defaults to :session" do
      expect(Clowk::Configuration.new.token_store).to eq(:session)
    end
  end

  describe "freshness (0.7)" do
    let(:tokens) { instance_double(Clowk::SDK::Token) }

    def broker(status)
      sdk_client = double("Clowk::SDK::Client")

      allow(Clowk::SDK::Client).to receive(:new).and_return(sdk_client)
      allow(sdk_client).to receive(:tokens).and_return(tokens)
      allow(tokens).to receive(:verify_with_session).and_return({session: status})
    end

    def signed_in(extras = {})
      dummy_class.new(
        session_data: {user: payload.merge("session_id" => "clk_session_abc")}.merge(extras),
        request: request
      )
    end

    before { Clowk.configure { |config| config.secret_key = "sk_test" } }

    describe "forcing a check" do
      before { Clowk.configure { |config| config.session_status_ttl = 300 } }

      it "takes the cached status by default, without asking Clowk" do
        broker({status: "active", session_id: "clk_session_abc"})

        instance = signed_in("session_status" => {"status" => "revoked"},
          "session_status_checked_at" => Time.now.to_i)

        expect(instance.clowk_session_active?).to be(false)
        expect(tokens).not_to have_received(:verify_with_session)
      end

      # The whole reason for 0.7. An app can now cache the ordinary check and
      # still demand a live answer where a stale "active" would be a hole.
      it "ignores the cache when forced, and asks Clowk" do
        broker({status: "revoked", session_id: "clk_session_abc"})

        instance = signed_in("session_status" => {"status" => "active"},
          "session_status_checked_at" => Time.now.to_i)

        expect(instance.clowk_session_active?).to be(true)
        expect(instance.clowk_session_active?(force: true)).to be(false)
        expect(tokens).to have_received(:verify_with_session).once
      end

      it "ends the session when the forced check comes back inactive" do
        broker({status: "revoked", session_id: "clk_session_abc"})

        instance = signed_in("session_status" => {"status" => "active"},
          "session_status_checked_at" => Time.now.to_i)

        instance.clowk_enforce_session!

        expect(instance.redirect_target).to be_nil

        instance.clowk_enforce_fresh_session!

        expect(instance.redirect_target).to eq("/clowk/sign_in?return_to=%2Fdashboard")
      end
    end

    describe "failing open when the broker cannot be reached" do
      before { Clowk.configure { |config| config.session_status_ttl = 300 } }

      def unreachable
        sdk_client = double("Clowk::SDK::Client")

        allow(Clowk::SDK::Client).to receive(:new).and_return(sdk_client)
        allow(sdk_client).to receive(:tokens).and_return(tokens)
        allow(tokens).to receive(:verify_with_session).and_raise(Errno::ECONNREFUSED)
      end

      it "leaves the session standing rather than signing everyone out" do
        unreachable

        instance = signed_in

        expect(instance.clowk_session_active?).to be(true)

        instance.clowk_enforce_session!

        expect(instance.redirect_target).to be_nil
      end

      it "can be switched off, for an app that would rather fail closed" do
        Clowk.configure { |config| config.fail_open_on_broker_error = false }
        unreachable

        expect(signed_in.clowk_session_active?).to be(false)
      end

      # A bug must not read as "the session is probably fine".
      it "does not swallow anything but a network failure" do
        sdk_client = double("Clowk::SDK::Client")

        allow(Clowk::SDK::Client).to receive(:new).and_return(sdk_client)
        allow(sdk_client).to receive(:tokens).and_return(tokens)
        allow(tokens).to receive(:verify_with_session).and_raise(NoMethodError, "undefined method")

        expect { signed_in.clowk_session_active? }.to raise_error(NoMethodError)
      end
    end

    describe "max_session_age" do
      before { Clowk.configure { |config| config.session_status_ttl = 300 } }

      it "ends a session past the ceiling without asking Clowk" do
        broker({status: "active", session_id: "clk_session_abc"})
        Clowk.configure { |config| config.max_session_age = 3600 }

        instance = signed_in("signed_in_at" => Time.now.to_i - 7200)

        instance.clowk_enforce_session!

        expect(instance.redirect_target).to eq("/clowk/sign_in?return_to=%2Fdashboard")
        expect(tokens).not_to have_received(:verify_with_session)
      end

      it "leaves a session inside the ceiling alone" do
        broker({status: "active", session_id: "clk_session_abc"})
        Clowk.configure { |config| config.max_session_age = 3600 }

        instance = signed_in("signed_in_at" => Time.now.to_i - 60)

        instance.clowk_enforce_session!

        expect(instance.redirect_target).to be_nil
      end

      # The other half of failing open: without a ceiling, an unreachable Clowk
      # would keep a session alive forever.
      it "ends a stale session even while the broker is unreachable" do
        sdk_client = double("Clowk::SDK::Client")

        allow(Clowk::SDK::Client).to receive(:new).and_return(sdk_client)
        allow(sdk_client).to receive(:tokens).and_return(tokens)
        allow(tokens).to receive(:verify_with_session).and_raise(Errno::ECONNREFUSED)

        Clowk.configure { |config| config.max_session_age = 3600 }

        instance = signed_in("signed_in_at" => Time.now.to_i - 7200)

        instance.clowk_enforce_session!

        expect(instance.redirect_target).to eq("/clowk/sign_in?return_to=%2Fdashboard")
      end

      it "is off by default, leaving Clowk as the only authority" do
        expect(Clowk::Configuration.new.max_session_age).to be_nil
      end
    end

    describe "with no session at all" do
      before do
        Clowk.configure do |config|
          config.session_status_ttl = 300
          config.max_session_age = 3600
        end
      end

      def anonymous
        dummy_class.new(request: request)
      end

      # Reached as a before_action rather than through clowk_authenticate!, this
      # used to read "not active" and expire a session that never existed —
      # which on a page that skips the identity gate on purpose threw away the
      # return_to the redirect was carrying.
      it "does nothing rather than expiring a session that never existed" do
        instance = anonymous

        instance.clowk_enforce_session!

        expect(instance.redirect_target).to be_nil
      end

      it "does nothing when forced either" do
        instance = anonymous

        instance.clowk_enforce_fresh_session!

        expect(instance.redirect_target).to be_nil
      end

      it "never reaches the callback" do
        seen = []

        Clowk.configure { |config| config.on_session_expired = ->(_c, info) { seen << info } }

        anonymous.clowk_enforce_session!

        expect(seen).to be_empty
      end

      it "still refuses the request when clowk_authenticate! is what asks" do
        instance = anonymous

        instance.clowk_authenticate!

        expect(instance.redirect_target).to eq("/clowk/sign_in?return_to=%2Fdashboard")
      end
    end

    it "routes every expiry through on_session_expired when one is set" do
      broker({status: "revoked", session_id: "clk_session_abc"})
      seen = []

      Clowk.configure do |config|
        config.max_session_age = 3600
        config.on_session_expired = ->(_controller, info) { seen << info }
      end

      signed_in("signed_in_at" => Time.now.to_i - 7200).clowk_enforce_session!
      signed_in.clowk_enforce_fresh_session!

      expect(seen.size).to eq(2)
    end
  end
end
