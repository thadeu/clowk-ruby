# frozen_string_literal: true

RSpec.describe Clowk::Configuration do
  subject(:configuration) { described_class.new }

  it 'defaults the client api_base_url to the public client API' do
    expect(configuration.api_base_url).to eq('https://api.clowk.dev/client/v1')
  end

  it 'defaults the callback_path to the oauth callback route' do
    expect(configuration.callback_path).to eq('/clowk/oauth/callback')
  end

  it 'defaults the http timeouts and retries' do
    expect(configuration.http_open_timeout).to eq(5)
    expect(configuration.http_read_timeout).to eq(10)
    expect(configuration.http_write_timeout).to eq(10)
    expect(configuration.http_retry_attempts).to eq(2)
    expect(configuration.http_retry_interval).to eq(0.05)
  end

  it 'defaults the prefix_by to clowk' do
    expect(configuration.prefix_by).to eq(:clowk)
  end

  it 'allows overriding the prefix_by' do
    configuration.prefix_by = :member

    expect(configuration.prefix_by).to eq(:member)
  end
end
