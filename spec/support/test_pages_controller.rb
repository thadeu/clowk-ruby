# frozen_string_literal: true

# A browser page behind the identity gate, to drive the refresh flow through
# the real cookie jar and session middleware.
class ClowkSpecPagesController < ActionController::Base
  include Clowk::Authenticable

  before_action :clowk_authenticate!

  def show
    render plain: "#{clowk_current_resource.email} #{current_token}"
  end
end
