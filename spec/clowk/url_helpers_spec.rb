# frozen_string_literal: true

RSpec.describe Clowk::Helpers::UrlHelpers do
  let(:request) do
    instance_double(
      "Request",
      base_url: "https://myapp.test"
    )
  end

  let(:helper_host) do
    Class.new do
      include Clowk::Helpers::UrlHelpers

      def initialize(request)
        @request = request
      end

      def request
        @request
      end
    end
  end

  it "builds the callback URL using the configured callback_path" do
    instance = helper_host.new(request)

    expect(instance.clowk_callback_url).to eq("https://myapp.test/clowk/oauth/callback")
  end

  it "uses the callback URL when building the remote sign in URL" do
    Clowk.configure do |config|
      config.instance_url = "https://acme.clowk.dev"
    end

    instance = helper_host.new(request)

    expect(instance.clowk_sign_in_url(redirect_to: "/dashboard")).to eq(
      "https://acme.clowk.dev/sign-in?redirect_uri=https%3A%2F%2Fmyapp.test%2Fclowk%2Foauth%2Fcallback%3Freturn_to%3D%252Fdashboard"
    )
  end

  it 'prioritizes publishable_key resolution over a hardcoded instance_url' do
    Clowk.configure do |config|
      config.publishable_key = 'pk_test_123'
      config.instance_url = 'https://hardcoded.clowk.dev'
    end

    instance = helper_host.new(request)

    allow(Clowk::Subdomain).to receive(:resolve_url!).and_return('https://latest.clowk.dev')

    expect(instance.clowk_sign_in_url).to eq(
      'https://latest.clowk.dev/sign-in?redirect_uri=https%3A%2F%2Fmyapp.test%2Fclowk%2Foauth%2Fcallback'
    )

    expect(Clowk::Subdomain).to have_received(:resolve_url!)
  end
end