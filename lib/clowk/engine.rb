# frozen_string_literal: true

module Clowk
  class Engine < ::Rails::Engine
    isolate_namespace Clowk

    initializer 'clowk.helpers' do
      ActiveSupport.on_load(:action_controller_base) do
        include Clowk::Helpers::UrlHelpers
      end

      ActiveSupport.on_load(:action_view) do
        include Clowk::Helpers::UrlHelpers
      end
    end
  end
end
