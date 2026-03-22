# frozen_string_literal: true

RSpec.describe Clowk::Subdomain do
  before do
    described_class.clear_cache!
  end

  it 'uses the publishable_key as the primary resolution source' do
    sdk = instance_double(Clowk::SDK)
    instances = instance_double(Clowk::Client::SDK::Resourceable::InstancesResource)

    Clowk.configure do |config|
      config.publishable_key = 'pk_test_123'
      config.instance_url = 'https://hardcoded.clowk.dev'
      config.api_base_url = 'https://api.clowk.in/client/v1'
    end

    redirect_response = Clowk::Http::Response.new(
      status: 302,
      body: '',
      body_parsed: {},
      headers: { 'location' => ['https://latest.clowk.dev'] },
      success: false
    )

    resolved_response = Clowk::Http::Response.new(
      status: 200,
      body: '',
      body_parsed: {},
      headers: {},
      success: true
    )

    allow(Clowk::SDK).to receive(:new).with(no_args).and_return(sdk)
    allow(sdk).to receive(:instances).and_return(instances)
    allow(instances).to receive(:find_by_key).with(path: 'i/pk_test_123').and_return(redirect_response)
    allow(instances).to receive(:find_by_key).with(path: 'https://latest.clowk.dev').and_return(resolved_response)

    expect(described_class.resolve_url!).to eq('https://latest.clowk.dev')
  end

  it 'falls back to the configured instance_url when publishable_key is absent' do
    Clowk.configure do |config|
      config.publishable_key = nil
      config.instance_url = 'https://acme.clowk.dev/'
    end

    expect(Clowk::SDK).not_to receive(:new)
    expect(described_class.resolve_url!).to eq('https://acme.clowk.dev')
  end

  it 'caches the resolved instance url for the configured ttl' do
    sdk = instance_double(Clowk::SDK)
    instances = instance_double(Clowk::Client::SDK::Resourceable::InstancesResource)

    Clowk.configure do |config|
      config.publishable_key = 'pk_test_123'
      config.api_base_url = 'https://api.clowk.in/client/v1'
    end

    redirect_response = Clowk::Http::Response.new(
      status: 302,
      body: '',
      body_parsed: {},
      headers: { 'location' => ['https://cached.clowk.dev'] },
      success: false
    )

    resolved_response = Clowk::Http::Response.new(
      status: 200,
      body: '',
      body_parsed: {},
      headers: {},
      success: true
    )

    allow(Clowk::SDK).to receive(:new).once.with(no_args).and_return(sdk)

    allow(sdk).to receive(:instances).and_return(instances)
    allow(instances).to receive(:find_by_key).with(path: 'i/pk_test_123').once.and_return(redirect_response)
    allow(instances).to receive(:find_by_key).with(path: 'https://cached.clowk.dev').once.and_return(resolved_response)

    first = described_class.resolve_url!
    second = described_class.resolve_url!

    expect(first).to eq('https://cached.clowk.dev')
    expect(second).to eq('https://cached.clowk.dev')
  end
end