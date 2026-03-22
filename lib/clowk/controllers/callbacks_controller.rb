# frozen_string_literal: true

module Clowk
  class CallbacksController < BaseController
    def show
      token = params[Clowk.config.token_param]
      raise Clowk::InvalidTokenError, 'missing token' if token.blank?

      payload = Clowk::JwtVerifier.new.verify(token)
      persist_clowk_session(token, payload)

      redirect_back_or(Clowk.config.after_sign_in_path)
    rescue Clowk::InvalidTokenError => e
      flash[:alert] = "Clowk authentication failed: #{e.message}"

      redirect_back_or(Clowk.config.after_sign_out_path)
    end
  end
end
