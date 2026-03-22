# frozen_string_literal: true

unless defined?(ClowkSpecApp)
  class ClowkSpecApp < Rails::Application
    config.root = File.expand_path("../support", __dir__)
    config.eager_load = false
    config.secret_key_base = "clowk_test_secret_key_base"
    config.hosts << "www.example.com"
    config.paths["config/routes.rb"] = File.expand_path("test_app_routes.rb", __dir__)
    config.session_store :cookie_store, key: "_clowk_test_session"
  end

  ClowkSpecApp.initialize!
end