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
  class Generation < BaseObservation
    # Gets the observation type
    #
    # @return [String] Always returns "generation"
    def type
      "generation"
    end

    # Updates this generation with new attributes
    #
    # @param attrs [Hash, Types::GenerationAttributes] Generation attributes to set
    # @return [self] Returns self for method chaining
    #
    # @example
    #   generation.update(
    #     output: { role: "assistant", content: "Hello!" },
    #     usage_details: { prompt_tokens: 100, completion_tokens: 50 }
    #   )
    def update(attrs)
      update_observation_attributes(attrs)
      self
    end

    # Convenience setters are inherited from BaseObservation

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
      update_observation_attributes(usage_details: value)
    end

    # Set the model name for this generation
    #
    # @param value [String] Model name (e.g., "gpt-4", "claude-3-opus")
    # @return [void]
    #
    # @example
    #   gen.model = "gpt-4"
    #
    def model=(value)
      update_observation_attributes(model: value)
    end

    # Set the model parameters for this generation
    #
    # @param value [Hash] Model parameters (temperature, max_tokens, etc.)
    # @return [void]
    #
    # @example
    #   gen.model_parameters = { temperature: 0.7, max_tokens: 100 }
    #
    def model_parameters=(value)
      update_observation_attributes(model_parameters: value)
    end

    # Convenience setters are inherited from BaseObservation
  end
end
