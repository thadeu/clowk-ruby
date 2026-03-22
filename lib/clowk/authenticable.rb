# frozen_string_literal: true

require 'active_support/concern'

module Clowk
  module Authenticable
    extend ActiveSupport::Concern

    def self.install_dynamic_methods(base)
      scope = Clowk.config.prefix_by.to_s
      current_method = :"current_#{scope}"
      authenticate_method = :"authenticate_#{scope}!"
      signed_in_method = :"#{scope}_signed_in?"

      base.class_eval do
        define_method(current_method) do
          clowk_current_resource
        end

        define_method(authenticate_method) do
          clowk_authenticate!
        end

        define_method(signed_in_method) do
          clowk_current_resource.present?
        end

        helper_method current_method, authenticate_method, signed_in_method, :current_token if respond_to?(:helper_method)
      end
    end

    included do
      Clowk::Authenticable.install_dynamic_methods(self)
    end

    def clowk_current_resource
      @clowk_current_resource ||= begin
        payload = stored_user_payload || verified_request_payload
        payload ? Current.new(payload) : nil
      end
    end

    def current_token
      stored_session&.dig('token') || extracted_token
    end

    def clowk_signed_in?
      clowk_current_resource.present?
    end

    def clowk_authenticate!
      return clowk_current_resource if clowk_signed_in?

      if request.format.json?
        render json: { error: 'Unauthorized' }, status: :unauthorized
      else
        redirect_to clowk_sign_in_path(return_to: request.fullpath)
      end
    end

    def clowk_sign_out!
      session.delete(Clowk.config.session_key)
      cookies.delete(Clowk.config.cookie_key)

      @clowk_current_resource = nil
    end

    private

    def verified_request_payload
      return unless extracted_token

      payload = Clowk::JwtVerifier.new.verify(extracted_token)
      persist_clowk_session(extracted_token, payload)

      payload
    rescue Clowk::InvalidTokenError
      nil
    end

    def extracted_token
      @extracted_token ||= Clowk::Middleware::TokenExtractor.new(request).call
    end

    def stored_session
      raw_session = session[Clowk.config.session_key]
      return unless raw_session.respond_to?(:to_h)

      raw_session.to_h
    end

    def stored_user_payload
      payload = stored_session&.dig('user') || stored_session&.dig(:user)
      payload&.deep_symbolize_keys
    end

    def persist_clowk_session(token, payload)
      session[Clowk.config.session_key] = {
        token: token,
        user: payload,
        signed_in_at: Time.now.to_i
      }

      cookies[Clowk.config.cookie_key] = {
        value: token,
        httponly: true,
        same_site: :lax,
        secure: request.ssl?
      }
    end
  end
end
