# frozen_string_literal: true

require "faraday"
require "base64"
require "json"

module Langfuse
  # HTTP client for Langfuse API
  #
  # Handles authentication, connection management, and HTTP requests
  # to the Langfuse REST API.
  #
  # @example
  #   api_client = Langfuse::ApiClient.new(
  #     public_key: "pk_...",
  #     secret_key: "sk_...",
  #     base_url: "https://cloud.langfuse.com",
  #     timeout: 5,
  #     logger: Logger.new($stdout)
  #   )
  #
  class ApiClient
    attr_reader :public_key, :secret_key, :base_url, :timeout, :logger, :cache

    # Initialize a new API client
    #
    # @param public_key [String] Langfuse public API key
    # @param secret_key [String] Langfuse secret API key
    # @param base_url [String] Base URL for Langfuse API
    # @param timeout [Integer] HTTP request timeout in seconds
    # @param logger [Logger] Logger instance for debugging
    # @param cache [PromptCache, nil] Optional cache for prompt responses
    # rubocop:disable Metrics/ParameterLists
    def initialize(public_key:, secret_key:, base_url:, timeout: 5, logger: nil, cache: nil)
      # rubocop:enable Metrics/ParameterLists
      @public_key = public_key
      @secret_key = secret_key
      @base_url = base_url
      @timeout = timeout
      @logger = logger || Logger.new($stdout, level: Logger::WARN)
      @cache = cache
    end

    # Get a Faraday connection
    #
    # @param timeout [Integer, nil] Optional custom timeout for this connection
    # @return [Faraday::Connection]
    def connection(timeout: nil)
      if timeout
        # Create dedicated connection for custom timeout
        # to avoid mutating shared connection
        build_connection(timeout: timeout)
      else
        @connection ||= build_connection
      end
    end

    # Fetch a prompt from the Langfuse API
    #
    # Checks cache first if caching is enabled. On cache miss, fetches from API
    # and stores in cache.
    #
    # @param name [String] The name of the prompt
    # @param version [Integer, nil] Optional specific version number
    # @param label [String, nil] Optional label (e.g., "production", "latest")
    # @return [Hash] The prompt data
    # @raise [ArgumentError] if both version and label are provided
    # @raise [NotFoundError] if the prompt is not found
    # @raise [UnauthorizedError] if authentication fails
    # @raise [ApiError] for other API errors
    # rubocop:disable Metrics/AbcSize
    def get_prompt(name, version: nil, label: nil)
      # rubocop:enable Metrics/AbcSize
      raise ArgumentError, "Cannot specify both version and label" if version && label

      # Check cache first if enabled
      if cache
        cache_key = PromptCache.build_key(name, version: version, label: label)
        cached_data = cache.get(cache_key)
        return cached_data if cached_data
      end

      # Fetch from API
      params = build_prompt_params(version: version, label: label)
      path = "/api/public/v2/prompts/#{name}"

      response = connection.get(path, params)
      prompt_data = handle_response(response)

      # Store in cache if enabled
      cache&.set(cache_key, prompt_data)

      prompt_data
    rescue Faraday::Error => e
      logger.error("Faraday error: #{e.message}")
      raise ApiError, "HTTP request failed: #{e.message}"
    end

    private

    # Build a new Faraday connection
    #
    # @param timeout [Integer, nil] Optional timeout override
    # @return [Faraday::Connection]
    def build_connection(timeout: nil)
      Faraday.new(
        url: base_url,
        headers: default_headers
      ) do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        conn.adapter Faraday.default_adapter
        conn.options.timeout = timeout || @timeout
      end
    end

    # Default headers for all requests
    #
    # @return [Hash]
    def default_headers
      {
        "Authorization" => authorization_header,
        "User-Agent" => user_agent,
        "Content-Type" => "application/json"
      }
    end

    # Generate Basic Auth header
    #
    # @return [String] Basic Auth header value
    def authorization_header
      credentials = "#{public_key}:#{secret_key}"
      "Basic #{Base64.strict_encode64(credentials)}"
    end

    # User agent string
    #
    # @return [String]
    def user_agent
      "langfuse-ruby/#{Langfuse::VERSION}"
    end

    # Build query parameters for prompt request
    #
    # @param version [Integer, nil] Optional version number
    # @param label [String, nil] Optional label
    # @return [Hash] Query parameters
    def build_prompt_params(version: nil, label: nil)
      params = {}
      params[:version] = version if version
      params[:label] = label if label
      params
    end

    # Handle HTTP response and raise appropriate errors
    #
    # @param response [Faraday::Response] The HTTP response
    # @return [Hash] The parsed response body
    # @raise [NotFoundError] if status is 404
    # @raise [UnauthorizedError] if status is 401
    # @raise [ApiError] for other error statuses
    def handle_response(response)
      case response.status
      when 200
        response.body
      when 401
        raise UnauthorizedError, "Authentication failed. Check your API keys."
      when 404
        raise NotFoundError, "Prompt not found"
      else
        error_message = extract_error_message(response)
        raise ApiError, "API request failed (#{response.status}): #{error_message}"
      end
    end

    # Extract error message from response body
    #
    # @param response [Faraday::Response] The HTTP response
    # @return [String] The error message
    def extract_error_message(response)
      return "Unknown error" unless response.body.is_a?(Hash)

      response.body["message"] || response.body["error"] || "Unknown error"
    end
  end
end
