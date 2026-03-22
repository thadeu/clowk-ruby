# frozen_string_literal: true

require "clowk"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = ".rspec_status"
  config.order = :random
  Kernel.srand config.seed

  config.before do
    Clowk.reset!
  end
end