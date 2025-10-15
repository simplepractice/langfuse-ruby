# frozen_string_literal: true

require "faraday"
require "faraday/retry"
require "json"

module Langfuse
  # HTTP client for Langfuse ingestion API
  #
  # Handles batch ingestion of trace events to the Langfuse API.
  # Used by the Exporter to send OTel spans converted to Langfuse events.
  #
  # @example
  #   client = Langfuse::IngestionClient.new(
  #     public_key: "pk_...",
  #     secret_key: "sk_...",
  #     base_url: "https://cloud.langfuse.com"
  #   )
  #
  #   events = [
  #     { id: "123", type: "trace-create", body: {...} }
  #   ]
  #   client.send_batch(events)
  #
  class IngestionClient
    attr_reader :public_key, :secret_key, :base_url, :timeout, :logger

    # Initialize a new ingestion client
    #
    # @param public_key [String] Langfuse public API key
    # @param secret_key [String] Langfuse secret API key
    # @param base_url [String] Base URL for Langfuse API (default: https://cloud.langfuse.com)
    # @param timeout [Integer] Request timeout in seconds (default: 5)
    # @param logger [Logger] Logger instance (default: Logger.new($stdout))
    def initialize(public_key:, secret_key:, base_url: "https://cloud.langfuse.com", timeout: 5, logger: nil)
      @public_key = public_key
      @secret_key = secret_key
      @base_url = base_url
      @timeout = timeout
      @logger = logger || Logger.new($stdout)
    end

    # Send a batch of events to the ingestion API
    #
    # @param events [Array<Hash>] Array of event hashes to send
    # @return [Boolean] true if successful
    # @raise [ApiError] if the request fails
    #
    # @example
    #   events = [
    #     {
    #       id: "event-123",
    #       timestamp: "2025-10-15T10:00:00.000Z",
    #       type: "trace-create",
    #       body: {
    #         id: "trace-abc",
    #         name: "my-trace",
    #         user_id: "user-123"
    #       }
    #     }
    #   ]
    #   client.send_batch(events)
    def send_batch(events)
      return true if events.nil? || events.empty?

      response = connection.post("/api/public/ingestion") do |req|
        req.body = { batch: events }.to_json
      end

      raise ApiError, "Ingestion failed (#{response.status}): #{response.body}" unless response.success?

      true
    rescue Faraday::Error => e
      logger.error("Langfuse ingestion error: #{e.message}")
      raise ApiError, "Ingestion request failed: #{e.message}"
    end

    private

    # Create Faraday connection with retry logic
    #
    # @return [Faraday::Connection]
    def connection
      @connection ||= Faraday.new(url: base_url) do |faraday|
        # Request/Response middleware
        faraday.request :json
        faraday.response :json

        # Retry configuration (more aggressive for ingestion)
        faraday.request :retry,
                        max: 3,
                        interval: 0.5,
                        backoff_factor: 2,
                        methods: [:post],
                        exceptions: [
                          Faraday::TimeoutError,
                          Faraday::ConnectionFailed,
                          Faraday::RetriableResponse
                        ],
                        retry_statuses: [408, 429, 500, 502, 503, 504]

        # Headers
        faraday.headers["Authorization"] = authorization_header
        faraday.headers["Content-Type"] = "application/json"
        faraday.headers["User-Agent"] = user_agent

        # Timeout
        faraday.options.timeout = timeout

        faraday.adapter Faraday.default_adapter
      end
    end

    # Generate Basic Auth header
    #
    # @return [String] Base64-encoded Basic Auth header
    def authorization_header
      credentials = "#{public_key}:#{secret_key}"
      encoded = Base64.strict_encode64(credentials)
      "Basic #{encoded}"
    end

    # Generate User-Agent header
    #
    # @return [String]
    def user_agent
      "langfuse-ruby/#{Langfuse::VERSION}"
    end
  end
end
