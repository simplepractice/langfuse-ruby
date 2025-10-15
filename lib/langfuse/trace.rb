# frozen_string_literal: true

module Langfuse
  # Wrapper around an OpenTelemetry span representing a Langfuse trace
  #
  # Provides methods to create child spans and generations within a trace.
  #
  # @example
  #   Langfuse.trace(name: "my-trace") do |trace|
  #     trace.span(name: "retrieval") do |span|
  #       # Do work
  #     end
  #
  #     trace.generation(name: "llm-call", model: "gpt-4") do |gen|
  #       # Call LLM
  #     end
  #   end
  #
  class Trace
    attr_reader :otel_span, :otel_tracer

    # Initialize a new Trace wrapper
    #
    # @param otel_span [OpenTelemetry::SDK::Trace::Span] The underlying OTel span
    # @param otel_tracer [OpenTelemetry::SDK::Trace::Tracer] The OTel tracer
    def initialize(otel_span, otel_tracer)
      @otel_span = otel_span
      @otel_tracer = otel_tracer
    end

    # Create a child span
    #
    # @param name [String] Name of the span
    # @param input [Object, nil] Optional input data (will be JSON-encoded)
    # @param metadata [Hash, nil] Optional metadata
    # @param level [String] Log level (debug, default, warning, error)
    # @yield [span] Yields the span object to the block
    # @yieldparam span [Langfuse::Span] The span object
    # @return [Object] The return value of the block
    #
    # @example
    #   trace.span(name: "database-query", input: { query: "SELECT ..." }) do |span|
    #     result = database.query(...)
    #     span.output = result
    #   end
    #
    def span(name:, input: nil, metadata: nil, level: "default", &block)
      attributes = build_span_attributes(
        type: "span",
        input: input,
        metadata: metadata,
        level: level
      )

      @otel_tracer.in_span(name, attributes: attributes) do |otel_span|
        span_obj = Langfuse::Span.new(otel_span, @otel_tracer)
        block.call(span_obj)
      end
    end

    # Create a generation (LLM call) span
    #
    # @param name [String] Name of the generation
    # @param model [String] Model name (e.g., "gpt-4", "claude-3-opus")
    # @param input [Object, nil] Optional input (prompt/messages)
    # @param metadata [Hash, nil] Optional metadata
    # @param model_parameters [Hash, nil] Optional model parameters (temperature, etc.)
    # @param prompt [Langfuse::TextPromptClient, Langfuse::ChatPromptClient, nil] Optional prompt for auto-linking
    # @yield [generation] Yields the generation object to the block
    # @yieldparam generation [Langfuse::Generation] The generation object
    # @return [Object] The return value of the block
    #
    # @example
    #   trace.generation(name: "gpt4-call", model: "gpt-4") do |gen|
    #     response = openai.chat(...)
    #     gen.output = response.content
    #     gen.usage = { prompt_tokens: 100, completion_tokens: 50 }
    #   end
    #
    def generation(name:, model:, input: nil, metadata: nil, model_parameters: nil, prompt: nil, &block)
      attributes = build_generation_attributes(
        model: model,
        input: input,
        metadata: metadata,
        model_parameters: model_parameters,
        prompt: prompt
      )

      @otel_tracer.in_span(name, attributes: attributes) do |otel_span|
        generation_obj = Langfuse::Generation.new(otel_span)
        block.call(generation_obj)
      end
    end

    # Add an event to the trace
    #
    # @param name [String] Event name
    # @param input [Object, nil] Optional event data
    # @param level [String] Log level (debug, default, warning, error)
    # @return [void]
    #
    # @example
    #   trace.event(name: "user-feedback", input: { rating: "thumbs_up" })
    #
    def event(name:, input: nil, level: "default")
      attributes = {
        "langfuse.input" => input&.to_json,
        "langfuse.level" => level
      }.compact

      @otel_span.add_event(name, attributes: attributes)
    end

    # Access the underlying OTel span (for advanced users)
    #
    # @return [OpenTelemetry::SDK::Trace::Span]
    def current_span
      @otel_span
    end

    # Inject W3C Trace Context headers for distributed tracing
    #
    # @return [Hash] Headers to include in HTTP requests
    #
    # @example
    #   headers = trace.inject_context
    #   HTTParty.get(url, headers: headers)
    #
    def inject_context
      carrier = {}
      OpenTelemetry.propagation.inject(carrier)
      carrier
    end

    private

    # Build OTel attributes for a span
    #
    # @param type [String] Span type ("span" or "generation")
    # @param input [Object, nil]
    # @param metadata [Hash, nil]
    # @param level [String]
    # @return [Hash]
    def build_span_attributes(type:, input:, metadata:, level:)
      {
        "langfuse.type" => type,
        "langfuse.input" => input&.to_json,
        "langfuse.metadata" => metadata&.to_json,
        "langfuse.level" => level
      }.compact
    end

    # Build OTel attributes for a generation
    #
    # @param model [String]
    # @param input [Object, nil]
    # @param metadata [Hash, nil]
    # @param model_parameters [Hash, nil]
    # @param prompt [Langfuse::TextPromptClient, Langfuse::ChatPromptClient, nil]
    # @return [Hash]
    def build_generation_attributes(model:, input:, metadata:, model_parameters:, prompt:)
      attrs = {
        "langfuse.type" => "generation",
        "langfuse.model" => model,
        "langfuse.input" => input&.to_json,
        "langfuse.metadata" => metadata&.to_json,
        "langfuse.model_parameters" => model_parameters&.to_json
      }.compact

      # Auto-link prompt if provided
      if prompt.respond_to?(:name) && prompt.respond_to?(:version)
        attrs["langfuse.prompt_name"] = prompt.name
        attrs["langfuse.prompt_version"] = prompt.version.to_s
      end

      attrs
    end
  end
end
