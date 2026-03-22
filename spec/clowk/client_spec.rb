# frozen_string_literal: true

RSpec.describe Clowk::Client::SDK do
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

  it 'keeps Clowk::SDK as a public alias' do
    expect(Clowk::SDK).to eq(described_class)
  end

  describe '#verify_token' do
    it 'delegates token verification to the internal http client' do
      token_response = Clowk::Http::Response.new(
        status: 200,
        body: '{"valid":true}',
        body_parsed: { 'valid' => true },
        headers: {},
        success: true
      )

      allow(http_client).to receive(:post).with('tokens/verify', { token: 'jwt_token' }, headers: {}).and_return(token_response)

      result = client.verify_token(token: 'jwt_token')

      expect(result).to eq(token_response)
      expect(result.body_parsed).to eq({ 'valid' => true })
      expect(result).to be_success
    end
  end

  describe '#user' do
    it 'delegates get requests to the internal http client' do
      user_response = Clowk::Http::Response.new(
        status: 200,
        body: '{"id":"user_123"}',
        body_parsed: { 'id' => 'user_123' },
        headers: {},
        success: true
      )

      allow(http_client).to receive(:get).with('users/user_123', headers: {}).and_return(user_response)

      result = client.user('user_123')

      expect(result).to eq(user_response)
      expect(result.body_parsed['id']).to eq('user_123')
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

      client.user('user_123')

      expect(Clowk::Http).to have_received(:new)
    end
  end
end