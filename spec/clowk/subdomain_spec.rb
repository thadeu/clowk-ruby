# frozen_string_literal: true

RSpec.describe Clowk::Subdomain do
  before do
    described_class.clear_cache!
  end

  it 'uses the publishable_key as the primary resolution source' do
    sdk = double('Clowk::SDK::Client')
    subdomains = instance_double(Clowk::SDK::Subdomain)

    Clowk.configure do |config|
      config.publishable_key = 'pk_test_123'
      config.subdomain_url = 'https://hardcoded.clowk.dev'
      config.api_base_url = 'https://api.clowk.in/client/v1'
    end

    instance_response = Clowk::Http::Response.new(
      status: 200,
      body: '',
      body_parsed: { 'subdomain' => 'latest' },
      headers: {},
      success: true
    )

    allow(Clowk::SDK::Client).to receive(:new).with(no_args).and_return(sdk)
    allow(sdk).to receive(:subdomains).and_return(subdomains)
    allow(subdomains).to receive(:find_by_pk).with('pk_test_123').and_return(instance_response)

    expect(described_class.resolve_url!).to eq('https://latest.clowk.dev')
  end

  it 'falls back to the configured subdomain_url when publishable_key is absent' do
    Clowk.configure do |config|
      config.publishable_key = nil
      config.subdomain_url = 'https://acme.clowk.dev/'
    end

    expect(Clowk::SDK::Client).not_to receive(:new)
    expect(described_class.resolve_url!).to eq('https://acme.clowk.dev')
  end

  it 'caches the resolved instance url for the configured ttl' do
    sdk = double('Clowk::SDK::Client')
    subdomains = instance_double(Clowk::SDK::Subdomain)

    Clowk.configure do |config|
      config.publishable_key = 'pk_test_123'
      config.api_base_url = 'https://api.clowk.in/client/v1'
    end

    instance_response = Clowk::Http::Response.new(
      status: 200,
      body: '',
      body_parsed: { 'subdomain' => 'cached' },
      headers: {},
      success: true
    )

    allow(Clowk::SDK::Client).to receive(:new).once.with(no_args).and_return(sdk)

    allow(sdk).to receive(:subdomains).and_return(subdomains)
    allow(subdomains).to receive(:find_by_pk).with('pk_test_123').once.and_return(instance_response)

    first = described_class.resolve_url!
    second = described_class.resolve_url!

    expect(first).to eq('https://cached.clowk.dev')
    expect(second).to eq('https://cached.clowk.dev')
  end

  it 'supports full instance payloads nested under instance' do
    sdk = double('Clowk::SDK::Client')
    subdomains = instance_double(Clowk::SDK::Subdomain)

    Clowk.configure do |config|
      config.publishable_key = 'pk_test_123'
    end

    instance_response = Clowk::Http::Response.new(
      status: 200,
      body: '',
      body_parsed: { 'instance' => { 'subdomain' => 'nested' } },
      headers: {},
      success: true
    )

    allow(Clowk::SDK::Client).to receive(:new).with(no_args).and_return(sdk)
    allow(sdk).to receive(:subdomains).and_return(subdomains)
    allow(subdomains).to receive(:find_by_pk).with('pk_test_123').and_return(instance_response)

    expect(described_class.resolve_url!).to eq('https://nested.clowk.dev')
  end
end