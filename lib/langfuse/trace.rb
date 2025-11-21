# frozen_string_literal: true

module Langfuse
  # Trace observation representing the root of a Langfuse trace hierarchy.
  #
  # Extends BaseObservation to provide trace-specific functionality and methods
  # to create child spans and generations within a trace.
  #
  # @example Block-based API (auto-ends)
  #   Langfuse.trace(name: "my-trace") do |trace|
  #     trace.span(name: "retrieval") do |span|
  #       span.output = {...}
  #     end
  #
  #     trace.generation(name: "llm-call", model: "gpt-4") do |gen|
  #       gen.output = {...}
  #     end
  #   end
  #
  # @example Stateful API (manual end)
  #   trace = Langfuse.trace(name: "my-trace")
  #   span = trace.span(name: "retrieval")
  #   span.output = {...}
  #   span.end
  #
  class Trace < BaseObservation
    # Gets the observation type
    #
    # Overrides BaseObservation#type to return "trace" instead of reading from attributes.
    #
    # @return [String] Always returns "trace"
    def type
      "trace"
    end

    # Create a child span
    #
    # Supports both block-based (auto-ends) and stateful (manual end) APIs.
    #
    # @param name [String] Name of the span
    # @param input [Object, nil] Optional input data (will be JSON-encoded)
    # @param metadata [Hash, nil] Optional metadata
    # @param level [String] Log level (debug, default, warning, error)
    # @yield [span] Optional block that receives the span object
    # @yieldparam span [Langfuse::Span] The span object
    # @return [Langfuse::Span, Object] The span object (or block return value if block given)
    #
    # @example Block-based (auto-ends)
    #   trace.span(name: "database-query", input: { query: "SELECT ..." }) do |span|
    #     result = database.query(...)
    #     span.output = result
    #   end
    #
    # @example Stateful (manual end)
    #   span = trace.span(name: "database-query", input: { query: "SELECT ..." })
    #   result = database.query(...)
    #   span.output = result
    #   span.end
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
    # Supports both block-based (auto-ends) and stateful (manual end) APIs.
    #
    # @param name [String] Name of the generation
    # @param model [String] Model name (e.g., "gpt-4", "claude-3-opus")
    # @param input [Object, nil] Optional input (prompt/messages)
    # @param metadata [Hash, nil] Optional metadata
    # @param model_parameters [Hash, nil] Optional model parameters (temperature, etc.)
    # @param prompt [Langfuse::TextPromptClient, Langfuse::ChatPromptClient, nil] Optional prompt for auto-linking
    # @yield [generation] Optional block that receives the generation object
    # @yieldparam generation [Langfuse::Generation] The generation object
    # @return [Langfuse::Generation, Object] The generation object (or block return value if block given)
    #
    # @example Block-based (auto-ends)
    #   trace.generation(name: "gpt4-call", model: "gpt-4") do |gen|
    #     response = openai.chat(...)
    #     gen.output = response.content
    #     gen.usage = { prompt_tokens: 100, completion_tokens: 50 }
    #   end
    #
    # @example Stateful (manual end)
    #   gen = trace.generation(name: "gpt4-call", model: "gpt-4")
    #   response = openai.chat(...)
    #   gen.output = response.content
    #   gen.usage = { prompt_tokens: 100, completion_tokens: 50 }
    #   gen.end
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

    # Updates this trace with new attributes
    #
    # @param attrs [Hash, Types::TraceAttributes] Trace attributes to set
    # @return [self] Returns self for method chaining
    #
    # @example
    #   trace.update(
    #     user_id: "user-123",
    #     session_id: "session-456",
    #     tags: ["production", "api-v2"],
    #     metadata: { version: "2.1.0" }
    #   )
    def update(attrs)
      update_trace(attrs)
      self
    end

    # Set the user ID for this trace
    #
    # @param value [String] User identifier
    # @return [void]
    #
    # @example
    #   trace.user_id = "user-123"
    #
    def user_id=(value)
      update_trace(user_id: value)
    end

    # Set the session ID for this trace
    #
    # @param value [String] Session identifier
    # @return [void]
    #
    # @example
    #   trace.session_id = "session-456"
    #
    def session_id=(value)
      update_trace(session_id: value)
    end

    # Set tags for this trace
    #
    # @param value [Array<String>] Tags array
    # @return [void]
    #
    # @example
    #   trace.tags = ["production", "api-v2"]
    #
    def tags=(value)
      update_trace(tags: value)
    end

    # Set the input of this trace
    #
    # Overrides BaseObservation#input= to set trace-level attributes instead of
    # observation-level attributes. Trace-level input/output represent the overall
    # workflow's input/output, while observation-level attributes (used by spans
    # and generations) represent individual step inputs/outputs.
    #
    # @param value [Object] The input value (will be JSON-encoded)
    # @return [void]
    #
    # @example
    #   trace.input = { query: "What is Ruby?" }
    #
    def input=(value)
      update_trace(input: value)
    end

    # Set the output of this trace
    #
    # Overrides BaseObservation#output= to set trace-level attributes instead of
    # observation-level attributes. Trace-level input/output represent the overall
    # workflow's input/output, while observation-level attributes (used by spans
    # and generations) represent individual step inputs/outputs.
    #
    # @param value [Object] The output value (will be JSON-encoded)
    # @return [void]
    #
    # @example
    #   trace.output = { answer: "Ruby is a programming language" }
    #
    def output=(value)
      update_trace(output: value)
    end

    # Set metadata for this trace
    #
    # Overrides BaseObservation#metadata= to set trace-level attributes.
    #
    # @param value [Hash] Metadata hash (expanded into individual langfuse.trace.metadata.* attributes)
    # @return [void]
    #
    # @example
    #   trace.metadata = { source: "api", cache: "miss" }
    #
    def metadata=(value)
      update_trace(metadata: value)
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
  end
end
