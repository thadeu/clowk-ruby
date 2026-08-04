# frozen_string_literal: true

RSpec.describe Clowk::Engine do
  # The unauthenticated fallback calls clowk_sign_in_path. API-only apps never
  # load :action_controller_base, so without the :action_controller_api hook the
  # helper is missing and a failed authentication raises NoMethodError instead
  # of rendering a 401.
  describe "url helpers" do
    it "are mixed into ActionController::API" do
      expect(ActionController::API.ancestors).to include(Clowk::Helpers::UrlHelpers)
    end

    it "are mixed into ActionController::Base" do
      expect(ActionController::Base.ancestors).to include(Clowk::Helpers::UrlHelpers)
    end

    it "gives an API controller a usable sign-in path" do
      controller = Class.new(ActionController::API).new

      expect(controller.clowk_sign_in_path(return_to: "/api/v1/me"))
        .to eq("/clowk/sign_in?return_to=%2Fapi%2Fv1%2Fme")
    end
  end
end
