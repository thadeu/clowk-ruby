# frozen_string_literal: true

# A real ActionController::API, not a stand-in.
#
# The dummy class the unit specs use raises from `session`, which is not what
# Rails does: with no session middleware loaded, `request.session` still returns
# a Session object that responds to `[]`. Testing against the fake let a bug
# through where every unauthenticated API call answered 302 instead of 401.
class ClowkSpecApiController < ActionController::API
  include Clowk::Authenticable

  before_action :clowk_authenticate!

  def show
    render json: {sub: clowk_current_resource.id, email: clowk_current_resource.email}
  end
end
