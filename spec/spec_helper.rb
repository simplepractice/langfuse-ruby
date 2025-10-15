# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  # Maintain high coverage standards
  minimum_coverage 95
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
