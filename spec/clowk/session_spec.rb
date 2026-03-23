# frozen_string_literal: true

RSpec.describe Clowk::SDK::Session do
  subject(:resource) { described_class.new(http_client) }

  let(:http_client) { instance_double(Clowk::Http) }
  let(:ok_response) do
    Clowk::Http::Response.new(
      status: 200,
      body: '{"ok":true}',
      body_parsed: { 'ok' => true },
      headers: {},
      success: true
    )
  end

  describe '.resource_path' do
    it 'is sessions' do
      expect(described_class.resource_path).to eq('sessions')
    end
  end

  describe '#list' do
    it 'calls GET /sessions' do
      allow(http_client).to receive(:get).with('sessions', headers: {}).and_return(ok_response)

      result = resource.list

      expect(result).to eq(ok_response)
    end
  end

  describe '#find' do
    it 'calls GET /sessions/:id' do
      allow(http_client).to receive(:get).with('sessions/clk_session_abc', headers: {}).and_return(ok_response)

      result = resource.find('clk_session_abc')

      expect(result).to eq(ok_response)
    end
  end

  describe '#search' do
    it 'calls GET /sessions/search?email=...' do
      allow(http_client).to receive(:get)
        .with('sessions/search?email=jane%40example.com', headers: {})
        .and_return(ok_response)

      result = resource.search(email: 'jane@example.com')

      expect(result).to eq(ok_response)
    end

    it 'URL-encodes the email' do
      allow(http_client).to receive(:get)
        .with('sessions/search?email=user%2Btag%40example.com', headers: {})
        .and_return(ok_response)

      result = resource.search(email: 'user+tag@example.com')

      expect(result).to eq(ok_response)
    end
  end

  describe '#revoke' do
    it 'calls DELETE /sessions/:id' do
      revoke_response = Clowk::Http::Response.new(
        status: 200,
        body: '{"revoked":true}',
        body_parsed: { 'revoked' => true },
        headers: {},
        success: true
      )

      allow(http_client).to receive(:delete)
        .with('sessions/clk_session_abc', nil, headers: {})
        .and_return(revoke_response)

      result = resource.revoke('clk_session_abc')

      expect(result).to eq(revoke_response)
    end
  end
end
