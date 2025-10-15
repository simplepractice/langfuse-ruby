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
    # @return [TextPromptClient, ChatPromptClient] The prompt client
    # @raise [ArgumentError] if both version and label are provided
    # @raise [NotFoundError] if the prompt is not found
    # @raise [UnauthorizedError] if authentication fails
    # @raise [ApiError] for other API errors
    def get_prompt(name, version: nil, label: nil)
      prompt_data = api_client.get_prompt(name, version: version, label: label)
      build_prompt_client(prompt_data)
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
  end
end
