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
  class Span < BaseObservation
    # Gets the observation type
    #
    # @return [String] Always returns "span"
    def type
      "span"
    end

    # Updates this span with new attributes
    #
    # @param attrs [Hash, Types::SpanAttributes] Span attributes to set
    # @return [self] Returns self for method chaining
    #
    # @example
    #   span.update(
    #     output: { result: "success" },
    #     level: "DEFAULT",
    #     metadata: { duration: 150 }
    #   )
    def update(attrs)
      update_observation_attributes(attrs)
      self
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
    def span(name:, input: nil, metadata: nil, level: "default", &)
      attrs = {
        input: input,
        metadata: metadata,
        level: level
      }.compact

      start_observation(name, attrs, as_type: :span, &)
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
    def generation(name:, model:, input: nil, metadata: nil, model_parameters: nil, prompt: nil, &)
      attrs = {
        model: model,
        input: input,
        metadata: metadata,
        model_parameters: model_parameters,
        prompt: normalize_prompt(prompt)
      }.compact

      start_observation(name, attrs, as_type: :generation, &)
    end
  end
end
