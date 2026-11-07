# frozen_string_literal: true

module Clowk
  module SDK
    # The refresh token lifecycle. Authenticated with the publishable key: the
    # refresh token is the credential.
    #
    #   pair = client.session_tokens.exchange(token: sign_in_token)
    #   pair = client.session_tokens.refresh(refresh_token: pair[:refresh_token])
    #
    # Each pair is a Hash with :access_token, :refresh_token, :expires_in,
    # :refresh_expires_in and :session_id. A refused call raises
    # Clowk::InvalidTokenError.
    class SessionToken < Resource
      def self.resource_path
        "sessions"
      end

      # Trades the sign-in token from the callback for an access + refresh pair.
      def exchange(token:)
        pair_from(client.post("#{self.class.resource_path}/exchange", {token: token}))
      end

      # Spends the refresh token and returns its successor.
      def refresh(refresh_token:)
        pair_from(client.post("#{self.class.resource_path}/refresh", {refresh_token: refresh_token}))
      end

      # Ends the session the refresh token belongs to.
      def revoke(refresh_token:)
        client.post("#{self.class.resource_path}/revoke", {refresh_token: refresh_token})
      end

      private

      def pair_from(response)
        body = response.body_parsed

        unless response.success?
          message = body.is_a?(Hash) ? body["error"] : nil

          raise Clowk::InvalidTokenError, message || "session token request failed"
        end

        data = (body.is_a?(Hash) && body["data"].is_a?(Hash)) ? body["data"] : body
        pair = data.to_h.deep_symbolize_keys

        raise Clowk::InvalidTokenError, "session token response has no access_token" if pair[:access_token].blank?

        pair
      end
    end
  end
end
