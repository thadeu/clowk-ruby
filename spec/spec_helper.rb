# frozen_string_literal: true

require "clowk"
require "action_dispatch/testing/integration"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |file| require file }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = ".rspec_status"
  config.order = :random
  Kernel.srand config.seed

  config.before do
    Clowk.reset!
    Clowk.configure do |clowk|
      clowk.secret_key = "spec_secret_key"
      clowk.subdomain_url = "https://acme.clowk.dev"
      clowk.after_sign_in_path = "/after_sign_in"
      clowk.after_sign_out_path = "/after_sign_out"
      clowk.mount_path = "/clowk"
      clowk.callback_path = "/clowk/oauth/callback"
    end
  end
end