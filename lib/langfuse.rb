# frozen_string_literal: true

require_relative "langfuse/version"

# Langfuse Ruby SDK
#
# Official Ruby SDK for Langfuse, providing LLM tracing, observability,
# and prompt management capabilities.
#
# @example Global configuration (Rails initializer)
#   Langfuse.configure do |config|
#     config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
#     config.secret_key = ENV['LANGFUSE_SECRET_KEY']
#     config.cache_ttl = 120
#   end
#
# @example Using the global client
#   client = Langfuse.client
#   prompt = client.get_prompt("greeting")
#
module Langfuse
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ApiError < Error; end
  class NotFoundError < ApiError; end
  class UnauthorizedError < ApiError; end
end

require_relative "langfuse/config"
require_relative "langfuse/api_client"
require_relative "langfuse/text_prompt_client"

module Langfuse
  class << self
    attr_writer :configuration

    # Returns the global configuration object
    #
    # @return [Config] the global configuration
    def configuration
      @configuration ||= Config.new
    end

    # Configure Langfuse globally
    #
    # @yield [Config] the configuration object
    # @return [Config] the configured configuration
    #
    # @example
    #   Langfuse.configure do |config|
    #     config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
    #     config.secret_key = ENV['LANGFUSE_SECRET_KEY']
    #   end
    def configure
      yield(configuration)
      configuration
    end

    # Returns the global singleton client
    #
    # @return [Client] the global client instance
    def client
      @client ||= Client.new(configuration)
    end

    # Reset global configuration and client (useful for testing)
    #
    # @return [void]
    def reset!
      @configuration = nil
      @client = nil
    end
  end
end

# Require core components as we build them
# require_relative "langfuse/client"
# require_relative "langfuse/api_client"
# require_relative "langfuse/prompt_cache"
# require_relative "langfuse/text_prompt_client"
# require_relative "langfuse/chat_prompt_client"
