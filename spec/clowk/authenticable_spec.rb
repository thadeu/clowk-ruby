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
end
