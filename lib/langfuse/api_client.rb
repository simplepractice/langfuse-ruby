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
    attr_reader :public_key, :secret_key, :base_url, :timeout, :logger

    # Initialize a new API client
    #
    # @param public_key [String] Langfuse public API key
    # @param secret_key [String] Langfuse secret API key
    # @param base_url [String] Base URL for Langfuse API
    # @param timeout [Integer] HTTP request timeout in seconds
    # @param logger [Logger] Logger instance for debugging
    def initialize(public_key:, secret_key:, base_url:, timeout: 5, logger: nil)
      @public_key = public_key
      @secret_key = secret_key
      @base_url = base_url
      @timeout = timeout
      @logger = logger || Logger.new($stdout, level: Logger::WARN)
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
  end
end
