# frozen_string_literal: true

module Clowk
  class SessionsController < BaseController
    def new
      state = start_clowk_auth_flow!(return_to: params[:return_to])

      redirect_to clowk_sign_in_url(state:), allow_other_host: true
    end

    def sign_up
      state = start_clowk_auth_flow!(return_to: params[:return_to])

      redirect_to clowk_sign_up_url(state:), allow_other_host: true
    end

    def destroy
      clowk_sign_out!

      redirect_back_or(Clowk.config.after_sign_out_path)
    end
  end
end
