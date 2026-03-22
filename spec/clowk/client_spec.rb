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

  before do
    allow(Clowk::Http).to receive(:new).with(
      base_url: 'https://api.clowk.dev/client/v1',
      headers: {
        'X-Clowk-Secret-Key' => 'sk_test_123',
        'X-Clowk-Publishable-Key' => 'pk_test_123'
      },
      open_timeout: 5,
      read_timeout: 10,
      write_timeout: 10,
      retry_attempts: 2,
      retry_interval: 0.05
    ).and_return(http_client)
  end

  describe '#verify_token' do
    it 'delegates token verification to the internal http client' do
      allow(http_client).to receive(:post).with('tokens/verify', { token: 'jwt_token' }, headers: {}).and_return(status: 200, body: '{"valid":true}', body_parsed: { 'valid' => true }, success?: true)

      result = client.verify_token(token: 'jwt_token')

      expect(result).to eq(status: 200, body: '{"valid":true}', body_parsed: { 'valid' => true }, success?: true)
    end
  end

  describe '#user' do
    it 'delegates get requests to the internal http client' do
      allow(http_client).to receive(:get).with('users/user_123', headers: {}).and_return(status: 200, body: '{"id":"user_123"}', body_parsed: { 'id' => 'user_123' }, success?: true)

      result = client.user('user_123')

      expect(result).to eq(status: 200, body: '{"id":"user_123"}', body_parsed: { 'id' => 'user_123' }, success?: true)
    end
  end

  describe '#put' do
    it 'delegates put requests to the internal http client' do
      allow(http_client).to receive(:put).with('users/user_123', { name: 'Jane' }, headers: {}).and_return(status: 200, body: '{"updated":true}', body_parsed: { 'updated' => true }, success?: true)

      result = client.put('users/user_123', { name: 'Jane' })

      expect(result).to eq(status: 200, body: '{"updated":true}', body_parsed: { 'updated' => true }, success?: true)
    end
  end

  describe '#delete' do
    it 'delegates delete requests to the internal http client' do
      allow(http_client).to receive(:delete).with('users/user_123', nil, headers: {}).and_return(status: 204, body: '', body_parsed: {}, success?: true)

      result = client.delete('users/user_123')

      expect(result).to eq(status: 204, body: '', body_parsed: {}, success?: true)
    end
  end

  describe '#patch' do
    it 'delegates patch requests to the internal http client' do
      allow(http_client).to receive(:patch).with('users/user_123', { name: 'Jane' }, headers: {}).and_return(status: 200, body: '{"updated":true}', body_parsed: { 'updated' => true }, success?: true)

      result = client.patch('users/user_123', { name: 'Jane' })

      expect(result).to eq(status: 200, body: '{"updated":true}', body_parsed: { 'updated' => true }, success?: true)
    end
  end
end