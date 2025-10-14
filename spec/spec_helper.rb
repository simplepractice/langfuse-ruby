# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  # Coverage requirement will increase as we build out features
  # Target: 90% by Phase 6
  minimum_coverage 50
end

require "langfuse"
require "webmock/rspec"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Disable external HTTP requests by default
  WebMock.disable_net_connect!(allow_localhost: false)

  # Reset global Langfuse state before each test
  config.before do
    Langfuse.reset!
  end
end
