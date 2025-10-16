# frozen_string_literal: true

module Langfuse
  # Wrapper around an OpenTelemetry span representing a Langfuse span
  #
  # Provides methods to create child spans and generations, and set output.
  #
  # @example
  #   trace.span(name: "retrieval") do |span|
  #     results = search_database(query)
  #     span.output = results
  #
  #     span.generation(name: "summarize", model: "gpt-4") do |gen|
  #       # Nested generation
  #     end
  #   end
  #
  class Span
    attr_reader :otel_span, :otel_tracer

    # Initialize a new Span wrapper
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
    #   span.span(name: "nested-operation", input: { key: "value" }) do |nested_span|
    #     result = perform_operation()
    #     nested_span.output = result
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
    #   span.generation(name: "gpt4-call", model: "gpt-4") do |gen|
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

    # Add an event to the span
    #
    # @param name [String] Event name
    # @param input [Object, nil] Optional event data
    # @param level [String] Log level (debug, default, warning, error)
    # @return [void]
    #
    # @example
    #   span.event(name: "cache-hit", input: { key: "user:123" })
    #
    def event(name:, input: nil, level: "default")
      attributes = {
        "langfuse.observation.input" => input&.to_json,
        "langfuse.observation.level" => level
      }.compact

      @otel_span.add_event(name, attributes: attributes)
    end

    # Set the output of this span
    #
    # @param value [Object] The output value (will be JSON-encoded)
    # @return [void]
    #
    # @example
    #   span.output = { results: [...], count: 42 }
    #
    def output=(value)
      @otel_span.set_attribute("langfuse.observation.output", value.to_json)
    end

    # Set metadata for this span
    #
    # @param value [Hash] Metadata hash (expanded into individual langfuse.observation.metadata.* attributes)
    # @return [void]
    #
    # @example
    #   span.metadata = { source: "database", cache: "miss" }
    #
    def metadata=(value)
      value.each do |key, val|
        @otel_span.set_attribute("langfuse.observation.metadata.#{key}", val.to_s)
      end
    end

    # Set the level of this span
    #
    # @param value [String] Level (debug, default, warning, error)
    # @return [void]
    #
    # @example
    #   span.level = "warning"
    #
    def level=(value)
      @otel_span.set_attribute("langfuse.observation.level", value)
    end

    # Access the underlying OTel span (for advanced users)
    #
    # @return [OpenTelemetry::SDK::Trace::Span]
    def current_span
      @otel_span
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
      attrs = {
        "langfuse.observation.type" => type,
        "langfuse.observation.input" => input&.to_json,
        "langfuse.observation.level" => level
      }.compact

      # Add metadata as individual langfuse.observation.metadata.* attributes
      metadata&.each do |key, value|
        attrs["langfuse.observation.metadata.#{key}"] = value.to_s
      end

      attrs
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
        "langfuse.observation.type" => "generation",
        "langfuse.observation.model.name" => model,
        "langfuse.observation.input" => input&.to_json,
        "langfuse.observation.model.parameters" => model_parameters&.to_json
      }.compact

      # Add metadata as individual langfuse.observation.metadata.* attributes
      metadata&.each do |key, value|
        attrs["langfuse.observation.metadata.#{key}"] = value.to_s
      end

      # Auto-link prompt if provided
      if prompt.respond_to?(:name) && prompt.respond_to?(:version)
        attrs["langfuse.observation.prompt.name"] = prompt.name
        attrs["langfuse.observation.prompt.version"] = prompt.version.to_i
      end

      attrs
    end
  end
end
