# frozen_string_literal: true

require "opentelemetry/sdk"

module Langfuse
  # Ruby wrapper around OpenTelemetry tracer
  #
  # Provides a Ruby-first API for creating traces while using
  # OpenTelemetry SDK underneath for span management and context propagation.
  #
  # @example Basic usage
  #   tracer = Langfuse::Tracer.new
  #   tracer.trace(name: "my-trace", user_id: "user-123") do |trace|
  #     # trace operations
  #   end
  #
  class Tracer
    attr_reader :otel_tracer

    # Initialize a new Langfuse tracer
    #
    # @param otel_tracer [OpenTelemetry::SDK::Trace::Tracer, nil] Optional OTel tracer (will create default if nil)
    def initialize(otel_tracer: nil)
      @otel_tracer = otel_tracer || default_tracer
    end

    # Create a new trace (root span)
    #
    # @param name [String] Name of the trace
    # @param user_id [String, nil] Optional user ID
    # @param session_id [String, nil] Optional session ID
    # @param input [Object, nil] Optional input data (will be JSON-encoded)
    # @param output [Object, nil] Optional output data (will be JSON-encoded)
    # @param metadata [Hash, nil] Optional metadata hash
    # @param tags [Array<String>, nil] Optional tags array
    # @param context [OpenTelemetry::Context, nil] Optional parent context for distributed tracing
    # @yield [trace] Yields the trace object to the block
    # @yieldparam trace [Langfuse::Trace] The trace object
    # @return [Object] The return value of the block
    #
    # @example
    #   tracer.trace(name: "user-request", user_id: "user-123", input: { query: "..." }) do |trace|
    #     trace.span(name: "database-query") do |span|
    #       # Do work
    #     end
    #   end
    #
    def trace(name:, user_id: nil, session_id: nil, input: nil, output: nil, metadata: nil, tags: nil, context: nil,
              &block)
      attributes = build_trace_attributes(
        user_id: user_id,
        session_id: session_id,
        input: input,
        output: output,
        metadata: metadata,
        tags: tags
      )

      # Use provided context or current context
      parent_context = context || OpenTelemetry::Context.current

      # Create OTel span with Langfuse attributes
      OpenTelemetry::Context.with_current(parent_context) do
        @otel_tracer.in_span(name, attributes: attributes, &wrap_trace_block(block))
      end
    end

    private

    # Get the default OTel tracer
    #
    # @return [OpenTelemetry::SDK::Trace::Tracer]
    def default_tracer
      OpenTelemetry.tracer_provider.tracer("langfuse", Langfuse::VERSION)
    end

    # Build OTel attributes for a trace
    #
    # @param user_id [String, nil]
    # @param session_id [String, nil]
    # @param input [Object, nil]
    # @param output [Object, nil]
    # @param metadata [Hash, nil]
    # @param tags [Array<String>, nil]
    # @return [Hash]
    def build_trace_attributes(user_id:, session_id:, input:, output:, metadata:, tags:)
      {
        "langfuse.type" => "trace",
        "langfuse.user_id" => user_id,
        "langfuse.session_id" => session_id,
        "langfuse.input" => input&.to_json,
        "langfuse.output" => output&.to_json,
        "langfuse.metadata" => metadata&.to_json,
        "langfuse.tags" => tags&.to_json
      }.compact
    end

    # Wrap the user's block to inject a Trace object
    #
    # @param block [Proc] The user's block
    # @return [Proc] A wrapped block that receives the OTel span
    def wrap_trace_block(block)
      proc do |otel_span|
        trace = Langfuse::Trace.new(otel_span, @otel_tracer)
        block.call(trace)
      end
    end
  end
end
