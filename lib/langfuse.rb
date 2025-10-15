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
require_relative "langfuse/prompt_cache"
require_relative "langfuse/api_client"
require_relative "langfuse/ingestion_client"
require_relative "langfuse/exporter"
require_relative "langfuse/otel_setup"
require_relative "langfuse/tracer"
require_relative "langfuse/trace"
require_relative "langfuse/span"
require_relative "langfuse/generation"
require_relative "langfuse/text_prompt_client"
require_relative "langfuse/chat_prompt_client"
require_relative "langfuse/client"

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
    #     config.tracing_enabled = true
    #   end
    def configure
      yield(configuration)

      # Auto-initialize OpenTelemetry if tracing is enabled
      OtelSetup.setup(configuration) if configuration.tracing_enabled

      configuration
    end

    # Returns the global singleton client
    #
    # @return [Client] the global client instance
    def client
      @client ||= Client.new(configuration)
    end

    # Returns the global singleton tracer
    #
    # @return [Tracer] the global tracer instance
    def tracer
      @tracer ||= Tracer.new
    end

    # Create a trace using the global tracer
    #
    # @param name [String] Name of the trace
    # @param user_id [String, nil] Optional user ID
    # @param session_id [String, nil] Optional session ID
    # @param metadata [Hash, nil] Optional metadata hash
    # @param tags [Array<String>, nil] Optional tags array
    # @param context [OpenTelemetry::Context, nil] Optional parent context for distributed tracing
    # @yield [trace] Yields the trace object to the block
    # @yieldparam trace [Langfuse::Trace] The trace object
    # @return [Object] The return value of the block
    #
    # @example
    #   Langfuse.trace(name: "user-request", user_id: "user-123") do |trace|
    #     trace.span(name: "database-query") do |span|
    #       # Do work
    #     end
    #
    #     trace.generation(name: "llm-call", model: "gpt-4") do |gen|
    #       # Call LLM
    #     end
    #   end
    #
    def trace(name:, user_id: nil, session_id: nil, metadata: nil, tags: nil, context: nil, &block)
      tracer.trace(
        name: name,
        user_id: user_id,
        session_id: session_id,
        metadata: metadata,
        tags: tags,
        context: context,
        &block
      )
    end

    # Shutdown Langfuse and flush any pending traces
    #
    # Call this when shutting down your application to ensure
    # all traces are sent to Langfuse.
    #
    # @param timeout [Integer] Timeout in seconds
    # @return [void]
    #
    # @example In a Rails initializer or shutdown hook
    #   at_exit { Langfuse.shutdown }
    #
    def shutdown(timeout: 30)
      OtelSetup.shutdown(timeout: timeout)
    end

    # Force flush all pending traces
    #
    # @param timeout [Integer] Timeout in seconds
    # @return [void]
    def force_flush(timeout: 30)
      OtelSetup.force_flush(timeout: timeout)
    end

    # Reset global configuration and client (useful for testing)
    #
    # @return [void]
    def reset!
      OtelSetup.shutdown(timeout: 5) if OtelSetup.initialized?
      @configuration = nil
      @client = nil
      @tracer = nil
    end
  end
end
