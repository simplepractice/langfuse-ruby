# frozen_string_literal: true

module Langfuse
  # Main client for Langfuse SDK
  #
  # Provides a unified interface for interacting with the Langfuse API.
  # Handles prompt fetching and returns the appropriate prompt client
  # (TextPromptClient or ChatPromptClient) based on the prompt type.
  #
  # @example
  #   config = Langfuse::Config.new(
  #     public_key: "pk_...",
  #     secret_key: "sk_...",
  #     cache_ttl: 120
  #   )
  #   client = Langfuse::Client.new(config)
  #   prompt = client.get_prompt("greeting")
  #   compiled = prompt.compile(name: "Alice")
  #
  class Client
    attr_reader :config, :api_client

    # Initialize a new Langfuse client
    #
    # @param config [Config] Configuration object
    def initialize(config)
      @config = config
      @config.validate!

      # Create cache if enabled
      cache = create_cache if cache_enabled?

      # Create API client with cache
      @api_client = ApiClient.new(
        public_key: config.public_key,
        secret_key: config.secret_key,
        base_url: config.base_url,
        timeout: config.timeout,
        logger: config.logger,
        cache: cache
      )
    end

    # Fetch a prompt and return the appropriate client
    #
    # Fetches the prompt from the Langfuse API and returns either a
    # TextPromptClient or ChatPromptClient based on the prompt type.
    #
    # @param name [String] The name of the prompt
    # @param version [Integer, nil] Optional specific version number
    # @param label [String, nil] Optional label (e.g., "production", "latest")
    # @param fallback [String, Array, nil] Optional fallback prompt to use on error
    # @param type [Symbol, nil] Required when fallback is provided (:text or :chat)
    # @return [TextPromptClient, ChatPromptClient] The prompt client
    # @raise [ArgumentError] if both version and label are provided
    # @raise [ArgumentError] if fallback is provided without type
    # @raise [NotFoundError] if the prompt is not found and no fallback provided
    # @raise [UnauthorizedError] if authentication fails and no fallback provided
    # @raise [ApiError] for other API errors and no fallback provided
    #
    # @example With fallback for graceful degradation
    #   prompt = client.get_prompt("greeting", fallback: "Hello {{name}}!", type: :text)
    def get_prompt(name, version: nil, label: nil, fallback: nil, type: nil)
      # Validate fallback usage
      if fallback && !type
        raise ArgumentError, "type parameter is required when fallback is provided (use :text or :chat)"
      end

      # Try to fetch from API
      prompt_data = api_client.get_prompt(name, version: version, label: label)
      build_prompt_client(prompt_data)
    rescue ApiError, NotFoundError, UnauthorizedError => e
      # If no fallback, re-raise the error
      raise e unless fallback

      # Log warning and return fallback
      config.logger.warn("Langfuse API error for prompt '#{name}': #{e.message}. Using fallback.")
      build_fallback_prompt_client(name, fallback, type)
    end

    # Convenience method: fetch and compile a prompt in one call
    #
    # This is a shorthand for calling get_prompt followed by compile.
    # Returns the compiled prompt ready to use with your LLM.
    #
    # @param name [String] The name of the prompt
    # @param variables [Hash] Variables to substitute in the prompt
    # @param version [Integer, nil] Optional specific version number
    # @param label [String, nil] Optional label (e.g., "production", "latest")
    # @param fallback [String, Array, nil] Optional fallback prompt to use on error
    # @param type [Symbol, nil] Required when fallback is provided (:text or :chat)
    # @return [String, Array<Hash>] Compiled prompt (String for text, Array for chat)
    # @raise [ArgumentError] if both version and label are provided
    # @raise [ArgumentError] if fallback is provided without type
    # @raise [NotFoundError] if the prompt is not found and no fallback provided
    # @raise [UnauthorizedError] if authentication fails and no fallback provided
    # @raise [ApiError] for other API errors and no fallback provided
    #
    # @example Compile a text prompt
    #   text = client.compile_prompt("greeting", variables: { name: "Alice" })
    #   # => "Hello Alice!"
    #
    # @example Compile a chat prompt
    #   messages = client.compile_prompt("support-bot", variables: { company: "Acme" })
    #   # => [{ role: :system, content: "You are a support agent for Acme" }]
    #
    # @example With fallback
    #   text = client.compile_prompt(
    #     "greeting",
    #     variables: { name: "Alice" },
    #     fallback: "Hello {{name}}!",
    #     type: :text
    #   )
    def compile_prompt(name, variables: {}, version: nil, label: nil, fallback: nil, type: nil)
      prompt = get_prompt(name, version: version, label: label, fallback: fallback, type: type)
      prompt.compile(**variables)
    end

    private

    # Check if caching is enabled in configuration
    #
    # @return [Boolean]
    def cache_enabled?
      config.cache_ttl&.positive?
    end

    # Create a cache instance based on configuration
    #
    # @return [PromptCache]
    def create_cache
      PromptCache.new(
        ttl: config.cache_ttl,
        max_size: config.cache_max_size
      )
    end

    # Build the appropriate prompt client based on prompt type
    #
    # @param prompt_data [Hash] The prompt data from API
    # @return [TextPromptClient, ChatPromptClient]
    # @raise [ApiError] if prompt type is unknown
    def build_prompt_client(prompt_data)
      type = prompt_data["type"]

      case type
      when "text"
        TextPromptClient.new(prompt_data)
      when "chat"
        ChatPromptClient.new(prompt_data)
      else
        raise ApiError, "Unknown prompt type: #{type}"
      end
    end

    # Build a fallback prompt client from fallback data
    #
    # @param name [String] The prompt name
    # @param fallback [String, Array] The fallback prompt content
    # @param type [Symbol] The prompt type (:text or :chat)
    # @return [TextPromptClient, ChatPromptClient]
    # @raise [ArgumentError] if type is invalid
    def build_fallback_prompt_client(name, fallback, type)
      # Create minimal prompt data structure
      prompt_data = {
        "name" => name,
        "version" => 0,
        "type" => type.to_s,
        "prompt" => fallback,
        "labels" => [],
        "tags" => ["fallback"],
        "config" => {}
      }

      case type
      when :text
        TextPromptClient.new(prompt_data)
      when :chat
        ChatPromptClient.new(prompt_data)
      else
        raise ArgumentError, "Invalid type: #{type}. Must be :text or :chat"
      end
    end
  end
end
