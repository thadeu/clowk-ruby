# frozen_string_literal: true

require 'securerandom'
require 'uri'

module Clowk
  class BaseController < ActionController::Base
    include Clowk::Authenticable
    include Clowk::Helpers::UrlHelpers

    protect_from_forgery with: :exception

    private

    def redirect_back_or(default, return_to: params[:return_to])
      redirect_target = safe_redirect_path(return_to) || safe_redirect_path(default) || '/'

      redirect_to redirect_target
    end

    def start_clowk_auth_flow!(return_to: nil)
      sanitized_return_to = safe_redirect_path(return_to) || safe_redirect_path(Clowk.config.after_sign_in_path) || '/'
      state = SecureRandom.hex(32)

      session[:clowk_auth_flow] = {
        'state' => state,
        'return_to' => sanitized_return_to
      }

      state
    end

    def consume_clowk_auth_flow!
      flow = session.delete(:clowk_auth_flow)
      return {} unless flow.respond_to?(:to_h)

      flow.to_h
    end

    def validate_clowk_state!(expected_state, actual_state)
      raise Clowk::InvalidStateError, 'missing state' if actual_state.blank?
      raise Clowk::InvalidStateError, 'missing state' if expected_state.blank?
      raise Clowk::InvalidStateError, 'invalid state' unless state_matches?(expected_state, actual_state)
    end

    def state_matches?(expected_state, actual_state)
      return false if expected_state.bytesize != actual_state.bytesize

      ActiveSupport::SecurityUtils.secure_compare(expected_state, actual_state)
    end

    def safe_redirect_path(candidate)
      value = candidate.to_s
      return if value.empty?

      return value if value.start_with?('/') && !value.start_with?('//')

      uri = URI.parse(value)
      return unless uri.host == request.host && uri.scheme == request.scheme

      uri.request_uri
    rescue URI::InvalidURIError
      nil
    end

    def reset_clowk_session!
      reset_session
    end
  end
end
