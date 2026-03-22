# frozen_string_literal: true

RSpec.describe Clowk::SDK do
  subject(:client) do
    described_class.new(
      api_base_url: 'https://api.clowk.dev/client/v1',
      secret_key: 'sk_test_123',
      publishable_key: 'pk_test_123'
    )
  end

  let(:http_client) { instance_double(Clowk::Http) }
  let(:response) do
    Clowk::Http::Response.new(
      status: 200,
      body: '{"ok":true}',
      body_parsed: { 'ok' => true },
      headers: {},
      success: true
    )
  end

  before do
    allow(Clowk::Http).to receive(:new).with(
      base_url: 'https://api.clowk.dev/client/v1',
      headers: {
        'X-Clowk-Secret-Key' => 'sk_test_123',
        'X-Clowk-Publishable-Key' => 'pk_test_123'
      },
      logger: nil,
      open_timeout: 5,
      read_timeout: 10,
      write_timeout: 10,
      retry_attempts: 2,
      retry_interval: 0.05
    ).and_return(http_client)
  end

  it 'uses the new SDK as the public client entrypoint' do
    expect(described_class).to eq(Clowk::SDK)
  end

  describe '#users' do
    it 'provides a users resource' do
      allow(http_client).to receive(:get).with('users/user_123', headers: {}).and_return(response)

      resource_result = client.users.find('user_123')

      expect(resource_result).to eq(response)
    end
  end

  describe '#sessions' do
    it 'exposes a sessions resource' do
      expect(client.sessions).to be_a(Clowk::SDK::Session)
    end
  end

  describe '#subdomains' do
    it 'exposes a subdomains resource' do
      expect(client.subdomains).to be_a(Clowk::SDK::Subdomain)
    end
  end

  describe '#users' do
    it 'exposes a users resource' do
      expect(client.users).to be_a(Clowk::SDK::User)
    end
  end

  describe '#tokens' do
    it 'exposes a tokens resource' do
      expect(client.tokens).to be_a(Clowk::SDK::Token)
    end

    it 'supports token verification through the token resource' do
      token_response = Clowk::Http::Response.new(
        status: 200,
        body: '{"valid":true}',
        body_parsed: { 'valid' => true },
        headers: {},
        success: true
      )

      allow(http_client).to receive(:post).with('tokens/verify', { token: 'jwt_token' }, headers: {}).and_return(token_response)

      result = client.tokens.verify(token: 'jwt_token')

      expect(result).to eq(token_response)
      expect(result.body_parsed).to eq({ 'valid' => true })
      expect(result).to be_success
    end
  end

  describe '#put' do
    it 'delegates put requests to the internal http client' do
      allow(http_client).to receive(:put).with('users/user_123', { name: 'Jane' }, headers: {}).and_return(response)

      result = client.put('users/user_123', { name: 'Jane' })

      expect(result).to eq(response)
    end
  end

  describe '#delete' do
    it 'delegates delete requests to the internal http client' do
      delete_response = Clowk::Http::Response.new(
        status: 204,
        body: '',
        body_parsed: {},
        headers: {},
        success: true
      )

      allow(http_client).to receive(:delete).with('users/user_123', nil, headers: {}).and_return(delete_response)

      result = client.delete('users/user_123')

      expect(result).to eq(delete_response)
    end
  end

  describe '#patch' do
    it 'delegates patch requests to the internal http client' do
      allow(http_client).to receive(:patch).with('users/user_123', { name: 'Jane' }, headers: {}).and_return(response)

      result = client.patch('users/user_123', { name: 'Jane' })

      expect(result).to eq(response)
    end
  end

  describe '#head' do
    it 'delegates head requests to the internal http client' do
      head_response = Clowk::Http::Response.new(
        status: 200,
        body: '',
        body_parsed: {},
        headers: { 'etag' => ['abc'] },
        success: true
      )

      allow(http_client).to receive(:head).with('users/user_123', headers: {}).and_return(head_response)

      result = client.head('users/user_123')

      expect(result).to eq(head_response)
      expect(result.headers['etag']).to eq(['abc'])
    end
  end

  describe '#options' do
    it 'delegates options requests to the internal http client' do
      options_response = Clowk::Http::Response.new(
        status: 200,
        body: '',
        body_parsed: {},
        headers: { 'allow' => ['GET,POST'] },
        success: true
      )

      allow(http_client).to receive(:options).with('users', headers: {}).and_return(options_response)

      result = client.options('users')

      expect(result).to eq(options_response)
      expect(result.headers['allow']).to eq(['GET,POST'])
    end
  end

  describe 'configured logger' do
    it 'passes the configured logger to the internal http client' do
      logger = instance_double(Logger)

      Clowk.configure do |config|
        config.http_logger = logger
      end

      allow(Clowk::Http).to receive(:new).with(
        base_url: 'https://api.clowk.dev/client/v1',
        headers: {
          'X-Clowk-Secret-Key' => 'sk_test_123',
          'X-Clowk-Publishable-Key' => 'pk_test_123'
        },
        logger: logger,
        open_timeout: 5,
        read_timeout: 10,
        write_timeout: 10,
        retry_attempts: 2,
        retry_interval: 0.05
      ).and_return(http_client)
      allow(http_client).to receive(:get).with('users/user_123', headers: {}).and_return(response)

      client.users.find('user_123')

      expect(Clowk::Http).to have_received(:new)
    end
  end
end