# frozen_string_literal: true

module Clowk
  class CallbacksController < BaseController
    def show
      flow = consume_clowk_auth_flow!
      validate_clowk_state!(flow["state"], params[:state])

      token = params[Clowk.config.token_param]
      raise Clowk::InvalidTokenError, "missing token" if token.blank?

      payload = Clowk::JwtVerifier.new.verify(token)
      return_to = flow["return_to"]

      reset_clowk_session!
      persist_clowk_session(token, payload)

      redirect_back_or(Clowk.config.after_sign_in_path, return_to:)
    rescue Clowk::InvalidTokenError, Clowk::InvalidStateError => e
      Rails.logger.error("[Clowk] Authentication failed: #{e.class} - #{e.message}")
      flash[:alert] = "Authentication failed. Please try again."

      redirect_back_or(Clowk.config.after_sign_out_path, return_to: nil)
    end
  end
end
