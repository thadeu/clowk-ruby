# frozen_string_literal: true

module Clowk
  class BaseController < ActionController::Base
    include Clowk::Authenticable
    include Clowk::Helpers::UrlHelpers

    protect_from_forgery with: :exception

    private

    def redirect_back_or(default)
      redirect_target = params[:return_to].presence || default

      redirect_to redirect_target, allow_other_host: true
    end
  end
end
