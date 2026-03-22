# frozen_string_literal: true

module RequestHelpers
  def integration_session
    ActionDispatch::Integration::Session.new(ClowkSpecApp)
  end

  def issued_token(payload = {})
    claims = {
      sub: "user_123",
      email: "user@example.com",
      name: "Jane Doe",
      iss: Clowk.config.issuer,
      exp: 1.hour.from_now.to_i
    }.merge(payload)

    JWT.encode(claims, Clowk.config.secret_key, Clowk::JwtVerifier::ALGORITHM)
  end
end

RSpec.configure do |config|
  config.include RequestHelpers
end