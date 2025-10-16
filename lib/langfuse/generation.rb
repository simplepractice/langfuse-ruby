# frozen_string_literal: true

module Langfuse
  # Wrapper around an OpenTelemetry span representing a Langfuse generation (LLM call)
  #
  # Provides methods to set output, usage, and other LLM-specific metadata.
  #
  # @example
  #   trace.generation(name: "gpt4-call", model: "gpt-4") do |gen|
  #     response = openai.chat(messages: [...])
  #     gen.output = response.choices.first.message.content
  #     gen.usage = {
  #       prompt_tokens: response.usage.prompt_tokens,
  #       completion_tokens: response.usage.completion_tokens,
  #       total_tokens: response.usage.total_tokens
  #     }
  #   end
  #
  class Generation
    attr_reader :otel_span

    # Initialize a new Generation wrapper
    #
    # @param otel_span [OpenTelemetry::SDK::Trace::Span] The underlying OTel span
    def initialize(otel_span)
      @otel_span = otel_span
    end

    # Set the output of this generation
    #
    # @param value [Object] The output value (will be JSON-encoded)
    # @return [void]
    #
    # @example
    #   gen.output = "Hello, how can I help you today?"
    #
    # @example with structured output
    #   gen.output = { role: "assistant", content: "Hello!" }
    #
    def output=(value)
      @otel_span.set_attribute("langfuse.observation.output", value.to_json)
    end

    # Set the usage statistics for this generation
    #
    # @param value [Hash] Usage hash with token counts
    # @option value [Integer] :prompt_tokens Number of tokens in the prompt
    # @option value [Integer] :completion_tokens Number of tokens in the completion
    # @option value [Integer] :total_tokens Total number of tokens
    # @return [void]
    #
    # @example
    #   gen.usage = {
    #     prompt_tokens: 100,
    #     completion_tokens: 50,
    #     total_tokens: 150
    #   }
    #
    def usage=(value)
      @otel_span.set_attribute("langfuse.observation.usage_details", value.to_json)
    end

    # Set metadata for this generation
    #
    # @param value [Hash] Metadata hash (expanded into individual langfuse.observation.metadata.* attributes)
    # @return [void]
    #
    # @example
    #   gen.metadata = { finish_reason: "stop", model_version: "gpt-4-0613" }
    #
    def metadata=(value)
      value.each do |key, val|
        @otel_span.set_attribute("langfuse.observation.metadata.#{key}", val.to_s)
      end
    end

    # Set the level of this generation
    #
    # @param value [String] Level (debug, default, warning, error)
    # @return [void]
    #
    # @example
    #   gen.level = "warning" if response.finish_reason == "length"
    #
    def level=(value)
      @otel_span.set_attribute("langfuse.observation.level", value)
    end

    # Add an event to the generation
    #
    # @param name [String] Event name
    # @param input [Object, nil] Optional event data
    # @param level [String] Log level (debug, default, warning, error)
    # @return [void]
    #
    # @example
    #   gen.event(name: "streaming-started")
    #   gen.event(name: "token-received", input: { token: "Hello" })
    #
    def event(name:, input: nil, level: "default")
      attributes = {
        "langfuse.observation.input" => input&.to_json,
        "langfuse.observation.level" => level
      }.compact

      @otel_span.add_event(name, attributes: attributes)
    end

    # Access the underlying OTel span (for advanced users)
    #
    # @return [OpenTelemetry::SDK::Trace::Span]
    def current_span
      @otel_span
    end
  end
end
