# frozen_string_literal: true

require 'net/http'

RSpec.describe Clowk::Http do
  subject(:http_client) do
    described_class.new(
      base_url: 'https://api.clowk.dev/client/v1',
      headers: { 'X-Test-Header' => 'abc123' }
    )
  end

  let(:http) { instance_double('Net::HTTP') }
  let(:empty_success_response) do
    Clowk::Http::Response.new(
      status: 200,
      body: '',
      body_parsed: {},
      headers: {},
      success: true
    )
  end

  describe '.post' do
    it 'supports the class-level helper' do
      instance = instance_double(described_class)

      allow(described_class).to receive(:new).with(base_url: 'https://api.clowk.dev/client/v1', headers: { 'X-Test-Header' => 'abc123' }, logger: nil).and_return(instance)
      allow(instance).to receive(:post).with('tokens/verify', { token: 'jwt_token' }).and_return(empty_success_response)

      result = described_class.post(
        base_url: 'https://api.clowk.dev/client/v1',
        path: 'tokens/verify',
        body: { token: 'jwt_token' },
        headers: { 'X-Test-Header' => 'abc123' }
      )

      expect(result).to eq(empty_success_response)
    end
  end

  describe '.get' do
    it 'supports the class-level helper' do
      instance = instance_double(described_class)

      allow(described_class).to receive(:new).with(base_url: 'https://api.clowk.dev/client/v1', headers: { 'X-Test-Header' => 'abc123' }, logger: nil).and_return(instance)
      allow(instance).to receive(:get).with('users/user_123').and_return(empty_success_response)

      result = described_class.get(
        base_url: 'https://api.clowk.dev/client/v1',
        path: 'users/user_123',
        headers: { 'X-Test-Header' => 'abc123' }
      )

      expect(result).to eq(empty_success_response)
    end
  end

  describe '.put' do
    it 'supports the class-level helper' do
      instance = instance_double(described_class)

      allow(described_class).to receive(:new).with(base_url: 'https://api.clowk.dev/client/v1', headers: { 'X-Test-Header' => 'abc123' }, logger: nil).and_return(instance)
      allow(instance).to receive(:put).with('users/user_123', { name: 'Jane' }).and_return(empty_success_response)

      result = described_class.put(
        base_url: 'https://api.clowk.dev/client/v1',
        path: 'users/user_123',
        body: { name: 'Jane' },
        headers: { 'X-Test-Header' => 'abc123' }
      )

      expect(result).to eq(empty_success_response)
    end
  end

  describe '#get' do
    it 'performs a get request and parses JSON' do
      response = Net::HTTPSuccess.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return('{"id":"user_123"}')
      allow(response).to receive(:to_hash).and_return({})

      allow(Net::HTTP).to receive(:start).with('api.clowk.dev', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:write_timeout=)
      allow(http).to receive(:request) do |request|
        expect(request).to be_a(Net::HTTP::Get)
        expect(request.path).to eq('/client/v1/users/user_123')
        expect(request['Accept']).to eq('application/json')
        expect(request['Content-Type']).to eq('application/json')
        expect(request['X-Test-Header']).to eq('abc123')
        response
      end

      result = http_client.get('users/user_123')

      expect(result.status).to eq(200)
      expect(result.body_parsed).to eq({ 'id' => 'user_123' })
      expect(result.headers).to eq({})
      expect(result).to be_success
    end
  end

  describe '#post' do
    it 'sends JSON and parses the response' do
      response = Net::HTTPSuccess.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return('{"valid":true}')
      allow(response).to receive(:to_hash).and_return({})

      allow(Net::HTTP).to receive(:start).with('api.clowk.dev', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:write_timeout=)
      allow(http).to receive(:request) do |request|
        expect(request).to be_a(Net::HTTP::Post)
        expect(request.path).to eq('/client/v1/tokens/verify')
        expect(request.body).to eq('{"token":"jwt_token"}')
        response
      end

      result = http_client.post('tokens/verify', { token: 'jwt_token' })

      expect(result.status).to eq(200)
      expect(result.body).to eq('{"valid":true}')
      expect(result.body_parsed).to eq({ 'valid' => true })
      expect(result).to be_success
    end
  end

  describe '#put' do
    it 'supports put requests' do
      response = Net::HTTPSuccess.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return('{"updated":true}')
      allow(response).to receive(:to_hash).and_return({})

      allow(Net::HTTP).to receive(:start).with('api.clowk.dev', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:write_timeout=)
      allow(http).to receive(:request) do |request|
        expect(request).to be_a(Net::HTTP::Put)
        expect(request.path).to eq('/client/v1/users/user_123')
        expect(request.body).to eq('{"name":"Jane"}')
        response
      end

      result = http_client.put('users/user_123', { name: 'Jane' })

      expect(result.status).to eq(200)
      expect(result.body_parsed).to eq({ 'updated' => true })
      expect(result).to be_success
    end
  end

  describe '#delete' do
    it 'supports delete requests' do
      response = Net::HTTPSuccess.new('1.1', '204', 'No Content')
      allow(response).to receive(:body).and_return('')
      allow(response).to receive(:to_hash).and_return({})

      allow(Net::HTTP).to receive(:start).with('api.clowk.dev', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:write_timeout=)
      allow(http).to receive(:request) do |request|
        expect(request).to be_a(Net::HTTP::Delete)
        expect(request.path).to eq('/client/v1/users/user_123')
        response
      end

      result = http_client.delete('users/user_123')

      expect(result.status).to eq(204)
      expect(result.body_parsed).to eq({})
      expect(result).to be_success
    end
  end

  describe '#head' do
    it 'supports head requests' do
      response = Net::HTTPSuccess.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return('')
      allow(response).to receive(:to_hash).and_return({ 'etag' => ['abc'] })

      allow(Net::HTTP).to receive(:start).with('api.clowk.dev', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:write_timeout=)
      allow(http).to receive(:request) do |request|
        expect(request).to be_a(Net::HTTP::Head)
        expect(request.path).to eq('/client/v1/users/user_123')
        response
      end

      result = http_client.head('users/user_123')

      expect(result.status).to eq(200)
      expect(result.headers).to eq({ 'etag' => ['abc'] })
      expect(result).to be_success
    end
  end

  describe '#options' do
    it 'supports options requests' do
      response = Net::HTTPSuccess.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return('')
      allow(response).to receive(:to_hash).and_return({ 'allow' => ['GET,POST,PUT,DELETE'] })

      allow(Net::HTTP).to receive(:start).with('api.clowk.dev', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:write_timeout=)
      allow(http).to receive(:request) do |request|
        expect(request).to be_a(Net::HTTP::Options)
        expect(request.path).to eq('/client/v1/users')
        response
      end

      result = http_client.options('users')

      expect(result.status).to eq(200)
      expect(result.headers).to eq({ 'allow' => ['GET,POST,PUT,DELETE'] })
      expect(result).to be_success
    end
  end

  describe '#post with plain text response' do
    it 'returns the raw body when the response is not JSON' do
      response = Net::HTTPBadRequest.new('1.1', '400', 'Bad Request')
      allow(response).to receive(:body).and_return('invalid request')
      allow(response).to receive(:to_hash).and_return({})

      allow(Net::HTTP).to receive(:start).with('api.clowk.dev', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:write_timeout=)
      allow(http).to receive(:request).and_return(response)

      result = http_client.post('tokens/verify', { token: 'jwt_token' })

      expect(result.status).to eq(400)
      expect(result.body).to eq('invalid request')
      expect(result.body_parsed).to be_nil
      expect(result).not_to be_success
    end
  end

  describe 'logger middleware' do
    it 'logs request and response information through middleware' do
      logger = instance_double(Logger)
      allow(logger).to receive(:info)

      response = Net::HTTPSuccess.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return('')
      allow(response).to receive(:to_hash).and_return({})

      allow(Net::HTTP).to receive(:start).with('api.clowk.dev', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:write_timeout=)
      allow(http).to receive(:request).and_return(response)

      described_class.new(base_url: 'https://api.clowk.dev/client/v1', logger: logger).get('users/user_123')

      expect(logger).to have_received(:info).with('[Clowk::Http] GET https://api.clowk.dev/client/v1/users/user_123')
      expect(logger).to have_received(:info).with('[Clowk::Http] -> 200')
    end
  end

  describe 'retry middleware' do
    it 'retries retryable failures before succeeding' do
      response = Net::HTTPSuccess.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return('{"ok":true}')
      allow(response).to receive(:to_hash).and_return({})

      allow(Net::HTTP).to receive(:start).with('api.clowk.dev', 443, use_ssl: true).and_yield(http)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:write_timeout=)

      attempts = 0
      allow(http).to receive(:request) do
        attempts += 1
        raise Net::ReadTimeout if attempts == 1

        response
      end

      allow_any_instance_of(Clowk::Http::RetryMiddleware).to receive(:sleep)

      result = http_client.get('users/user_123')

      expect(result.status).to eq(200)
      expect(result.body_parsed).to eq({ 'ok' => true })
      expect(result).to be_success
    end
  end

  describe 'timeout middleware' do
    it 'applies configured net/http timeouts' do
      response = Net::HTTPSuccess.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return('')
      allow(response).to receive(:to_hash).and_return({})

      custom_http = described_class.new(
        base_url: 'https://api.clowk.dev/client/v1',
        open_timeout: 7,
        read_timeout: 11,
        write_timeout: 13,
        middlewares: [Clowk::Http::TimeoutMiddleware]
      )

      allow(Net::HTTP).to receive(:start).with('api.clowk.dev', 443, use_ssl: true).and_yield(http)
      expect(http).to receive(:open_timeout=).with(7)
      expect(http).to receive(:read_timeout=).with(11)
      expect(http).to receive(:write_timeout=).with(13)
      allow(http).to receive(:request).and_return(response)

      result = custom_http.get('users/user_123')

      expect(result.status).to eq(200)
      expect(result.body_parsed).to eq({})
      expect(result).to be_success
    end
  end

  describe Clowk::Http::Response do
    it 'exposes a stable API and remains hash-compatible' do
      response = described_class.new(
        status: 201,
        body: '{"id":"user_123"}',
        body_parsed: { 'id' => 'user_123' },
        headers: { 'location' => ['/users/user_123'] },
        success: true
      )

      expect(response.status).to eq(201)
      expect(response.body_parsed['id']).to eq('user_123')
      expect(response[:success?]).to eq(true)
      expect(response.to_h).to eq(
        status: 201,
        body: '{"id":"user_123"}',
        body_parsed: { 'id' => 'user_123' },
        headers: { 'location' => ['/users/user_123'] },
        success?: true
      )
    end
  end
end