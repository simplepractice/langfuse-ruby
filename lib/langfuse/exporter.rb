# frozen_string_literal: true

require "opentelemetry/sdk"
require "securerandom"
require "json"

module Langfuse
  # OpenTelemetry exporter that converts OTel spans to Langfuse events
  #
  # This exporter implements the OpenTelemetry SpanExporter interface
  # and converts OTel spans to Langfuse's ingestion event format.
  #
  # @example Register with OTel SDK
  #   OpenTelemetry::SDK.configure do |c|
  #     c.add_span_processor(
  #       OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
  #         Langfuse::Exporter.new(
  #           public_key: "pk_...",
  #           secret_key: "sk_..."
  #         )
  #       )
  #     )
  #   end
  #
  # rubocop:disable Metrics/ClassLength
  class Exporter
    attr_reader :ingestion_client

    # Initialize a new Langfuse exporter
    #
    # @param public_key [String] Langfuse public API key
    # @param secret_key [String] Langfuse secret API key
    # @param base_url [String] Base URL for Langfuse API (default: https://cloud.langfuse.com)
    # @param logger [Logger] Logger instance (optional)
    def initialize(public_key:, secret_key:, base_url: "https://cloud.langfuse.com", logger: nil)
      @ingestion_client = IngestionClient.new(
        public_key: public_key,
        secret_key: secret_key,
        base_url: base_url,
        logger: logger
      )
      @logger = logger || Logger.new($stdout)
      # Cache of span_id -> langfuse.type to handle SimpleSpanProcessor exporting spans one-at-a-time
      # When a child span is exported before its parent, we can look up the parent's type from this cache
      @span_types_cache = {}
    end

    # Export spans to Langfuse (called by OTel BatchSpanProcessor)
    #
    # @param span_data_list [Array<OpenTelemetry::SDK::Trace::SpanData>] Array of span data
    # @param timeout [Integer, nil] Optional timeout in seconds
    # @return [Integer] Export result code (SUCCESS or FAILURE)
    def export(span_data_list, timeout: nil)
      return OpenTelemetry::SDK::Trace::Export::SUCCESS if span_data_list.nil? || span_data_list.empty?

      @logger.debug("=" * 80)
      @logger.debug("Langfuse Exporter: Exporting #{span_data_list.length} spans")

      # First pass: build a map of span_id -> langfuse.type for all spans in this export
      # and merge with the persistent cache
      current_batch_types = build_span_types_map(span_data_list)
      @span_types_cache.merge!(current_batch_types)
      @logger.debug("Span types (current batch): #{current_batch_types}")
      @logger.debug("Span types (cached): #{@span_types_cache}")

      events = span_data_list.map do |span_data|
        event = convert_span_to_event(span_data, @span_types_cache)
        if event
          @logger.debug("Created event: type=#{event[:type]}, body.id=#{event[:body][:id]}, " \
                        "body.trace_id=#{event[:body][:trace_id]}, " \
                        "body.parent_observation_id=#{event[:body][:parent_observation_id]}")
        end
        event
      end.compact

      @logger.debug("Sending batch with #{events.length} events")
      @logger.debug("Full batch payload: #{JSON.pretty_generate(events)}")

      @ingestion_client.send_batch(events)

      OpenTelemetry::SDK::Trace::Export::SUCCESS
    rescue StandardError => e
      @logger.error("Langfuse export failed: #{e.message}")
      @logger.debug("Backtrace: #{e.backtrace.join("\n")}")
      OpenTelemetry::SDK::Trace::Export::FAILURE
    end

    # Force flush any buffered spans (required by OTel interface)
    #
    # @param timeout [Integer, nil] Optional timeout in seconds
    # @return [Integer] Export result code (SUCCESS or FAILURE)
    def force_flush(timeout: nil)
      # No buffering in this exporter (handled by BatchSpanProcessor)
      OpenTelemetry::SDK::Trace::Export::SUCCESS
    end

    # Shutdown the exporter (required by OTel interface)
    #
    # @param timeout [Integer, nil] Optional timeout in seconds
    # @return [Integer] Export result code (SUCCESS or FAILURE)
    def shutdown(timeout: nil)
      # No cleanup needed
      OpenTelemetry::SDK::Trace::Export::SUCCESS
    end

    private

    # Build a map of span_id -> langfuse.type for all spans in this export batch
    #
    # This allows us to determine if a parent span is a trace when processing child spans,
    # even when spans are exported one-at-a-time (SimpleSpanProcessor) or in separate batches.
    #
    # @param span_data_list [Array<OpenTelemetry::SDK::Trace::SpanData>]
    # @return [Hash<String, String>] Map of hex-encoded span IDs to their langfuse.type
    def build_span_types_map(span_data_list)
      span_types = {}
      span_data_list.each do |span_data|
        attributes = extract_attributes(span_data)
        span_id_hex = format_span_id(span_data.span_id)
        langfuse_type = attributes["langfuse.type"] || "span"

        @logger.debug("  Span: name=#{span_data.name}, id=#{span_id_hex}, " \
                      "langfuse.type=#{langfuse_type}, " \
                      "parent_span_id=#{format_span_id(span_data.parent_span_id)}")

        span_types[span_id_hex] = langfuse_type if span_id_hex
      end
      span_types
    end

    # Convert an OTel span to a Langfuse ingestion event
    #
    # @param span_data [OpenTelemetry::SDK::Trace::SpanData] The span data
    # @param span_types [Hash<String, String>] Map of span IDs to their langfuse.type
    # @return [Hash, nil] The Langfuse event or nil if conversion fails
    def convert_span_to_event(span_data, span_types)
      attributes = extract_attributes(span_data)
      langfuse_type = attributes["langfuse.type"] || "span"

      case langfuse_type
      when "trace"
        create_trace_event(span_data, attributes)
      when "span"
        create_span_event(span_data, attributes, span_types)
      when "generation"
        create_generation_event(span_data, attributes, span_types)
      else
        @logger.warn("Unknown langfuse.type: #{langfuse_type}, treating as span")
        create_span_event(span_data, attributes, span_types)
      end
    rescue StandardError => e
      @logger.error("Failed to convert span to event: #{e.message}")
      nil
    end

    # Extract attributes from span data as a Hash
    #
    # @param span_data [OpenTelemetry::SDK::Trace::SpanData]
    # @return [Hash<String, Object>]
    def extract_attributes(span_data)
      return {} unless span_data.attributes

      # Convert OTel attributes to plain Hash
      span_data.attributes.transform_keys(&:to_s)
    end

    # Create a trace-create event
    #
    # @param span_data [OpenTelemetry::SDK::Trace::SpanData]
    # @param attributes [Hash]
    # @return [Hash]
    def create_trace_event(span_data, attributes)
      {
        id: SecureRandom.uuid,
        timestamp: format_timestamp(span_data.start_timestamp),
        type: "trace-create",
        body: {
          id: format_trace_id(span_data.trace_id),
          name: span_data.name,
          user_id: attributes["langfuse.user_id"],
          session_id: attributes["langfuse.session_id"],
          input: parse_json_attribute(attributes["langfuse.input"]),
          output: parse_json_attribute(attributes["langfuse.output"]),
          metadata: parse_json_attribute(attributes["langfuse.metadata"]),
          tags: parse_json_attribute(attributes["langfuse.tags"]),
          timestamp: format_timestamp(span_data.start_timestamp)
        }.compact
      }
    end

    # Create a span-create event
    #
    # @param span_data [OpenTelemetry::SDK::Trace::SpanData]
    # @param attributes [Hash]
    # @param span_types [Hash<String, String>] Map of span IDs to their langfuse.type
    # @return [Hash]
    def create_span_event(span_data, attributes, span_types)
      # Don't set parent_observation_id if parent is a trace (direct child of trace)
      parent_span_id_hex = format_span_id(span_data.parent_span_id)
      parent_type = span_types[parent_span_id_hex]

      parent_observation_id = if parent_span_id_hex && parent_type == "trace"
                                @logger.debug("    Parent type=#{parent_type} (#{parent_span_id_hex}) -> " \
                                              "parent_observation_id = nil")
                                nil
                              else
                                @logger.debug("    Parent type=#{parent_type} (#{parent_span_id_hex}) -> " \
                                              "parent_observation_id = #{parent_span_id_hex}")
                                parent_span_id_hex
                              end

      {
        id: SecureRandom.uuid,
        timestamp: format_timestamp(span_data.start_timestamp),
        type: "span-create",
        body: {
          id: format_span_id(span_data.span_id),
          trace_id: format_trace_id(span_data.trace_id),
          parent_observation_id: parent_observation_id,
          name: span_data.name,
          input: parse_json_attribute(attributes["langfuse.input"]),
          output: parse_json_attribute(attributes["langfuse.output"]),
          metadata: parse_json_attribute(attributes["langfuse.metadata"]),
          level: attributes["langfuse.level"] || "default",
          start_time: format_timestamp(span_data.start_timestamp),
          end_time: format_timestamp(span_data.end_timestamp),
          status_message: span_data.status&.description
        }.compact
      }
    end

    # Create a generation-create event
    #
    # @param span_data [OpenTelemetry::SDK::Trace::SpanData]
    # @param attributes [Hash]
    # @param span_types [Hash<String, String>] Map of span IDs to their langfuse.type
    # @return [Hash]
    def create_generation_event(span_data, attributes, span_types)
      # Don't set parent_observation_id if parent is a trace (direct child of trace)
      parent_span_id_hex = format_span_id(span_data.parent_span_id)
      parent_type = span_types[parent_span_id_hex]

      parent_observation_id = if parent_span_id_hex && parent_type == "trace"
                                @logger.debug("    Parent type=#{parent_type} (#{parent_span_id_hex}) -> " \
                                              "parent_observation_id = nil")
                                nil
                              else
                                @logger.debug("    Parent type=#{parent_type} (#{parent_span_id_hex}) -> " \
                                              "parent_observation_id = #{parent_span_id_hex}")
                                parent_span_id_hex
                              end

      {
        id: SecureRandom.uuid,
        timestamp: format_timestamp(span_data.start_timestamp),
        type: "generation-create",
        body: {
          id: format_span_id(span_data.span_id),
          trace_id: format_trace_id(span_data.trace_id),
          parent_observation_id: parent_observation_id,
          name: span_data.name,
          model: attributes["langfuse.model"],
          input: parse_json_attribute(attributes["langfuse.input"]),
          output: parse_json_attribute(attributes["langfuse.output"]),
          model_parameters: parse_json_attribute(attributes["langfuse.model_parameters"]),
          usage: extract_usage(attributes),
          prompt_name: attributes["langfuse.prompt_name"],
          prompt_version: attributes["langfuse.prompt_version"]&.to_i,
          start_time: format_timestamp(span_data.start_timestamp),
          end_time: format_timestamp(span_data.end_timestamp),
          completion_start_time: attributes["langfuse.completion_start_time"],
          level: attributes["langfuse.level"] || "default",
          status_message: span_data.status&.description
        }.compact
      }
    end

    # Extract usage information from attributes
    #
    # @param attributes [Hash]
    # @return [Hash, nil]
    def extract_usage(attributes)
      usage_json = attributes["langfuse.usage"]
      return nil unless usage_json

      parse_json_attribute(usage_json)
    end

    # Format OTel trace ID to hex string
    #
    # @param trace_id [String, nil] Binary trace ID
    # @return [String, nil] Hex-encoded trace ID
    def format_trace_id(trace_id)
      return nil if trace_id.nil?

      trace_id.unpack1("H*")
    end

    # Format OTel span ID to hex string
    #
    # @param span_id [String, nil] Binary span ID
    # @return [String, nil] Hex-encoded span ID
    def format_span_id(span_id)
      return nil if span_id.nil?

      span_id.unpack1("H*")
    end

    # Format OTel timestamp (nanoseconds since epoch) to ISO 8601
    #
    # @param timestamp [Integer, nil] Nanoseconds since epoch
    # @return [String, nil] ISO 8601 formatted timestamp
    def format_timestamp(timestamp)
      return nil if timestamp.nil?

      # Convert nanoseconds to seconds with fractional part
      seconds = timestamp / 1_000_000_000.0
      Time.at(seconds).utc.strftime("%Y-%m-%dT%H:%M:%S.%3NZ")
    end

    # Parse a JSON string attribute
    #
    # @param json_string [String, nil]
    # @return [Object, nil] Parsed JSON or nil
    def parse_json_attribute(json_string)
      return nil if json_string.nil?

      JSON.parse(json_string)
    rescue JSON::ParserError => e
      @logger.warn("Failed to parse JSON attribute: #{e.message}")
      nil
    end
  end
  # rubocop:enable Metrics/ClassLength
end
