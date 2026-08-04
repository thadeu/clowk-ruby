# frozen_string_literal: true

module Clowk
  class Engine < ::Rails::Engine
    isolate_namespace Clowk

    initializer "clowk.helpers" do
      ActiveSupport.on_load(:action_controller_base) do
        include Clowk::Helpers::UrlHelpers
      end

      # API-only apps never load :action_controller_base, so without this hook
      # clowk_sign_in_path — reached from the unauthenticated fallback — raises
      # NoMethodError instead of rendering a 401.
      ActiveSupport.on_load(:action_controller_api) do
        include Clowk::Helpers::UrlHelpers
      end

      ActiveSupport.on_load(:action_view) do
        include Clowk::Helpers::UrlHelpers
      end
    end
  end
end
