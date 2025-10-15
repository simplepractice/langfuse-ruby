# frozen_string_literal: true

require "opentelemetry/sdk"

module Langfuse
  # OpenTelemetry initialization and setup
  #
  # Handles configuration of the OTel SDK with Langfuse exporter
  # when tracing is enabled.
  #
  module OtelSetup
    class << self
      attr_reader :tracer_provider

      # Initialize OpenTelemetry with Langfuse exporter
      #
      # @param config [Langfuse::Config] The Langfuse configuration
      # @return [void]
      def setup(config)
        return unless config.tracing_enabled

        # Create Langfuse exporter
        exporter = Langfuse::Exporter.new(
          public_key: config.public_key,
          secret_key: config.secret_key,
          base_url: config.base_url,
          logger: config.logger
        )

        # Create processor based on async configuration
        processor = if config.tracing_async
                      # Async: BatchSpanProcessor batches and sends in background
                      OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
                        exporter,
                        max_queue_size: config.batch_size * 2, # Buffer more than batch_size
                        schedule_delay: config.flush_interval * 1000, # Convert seconds to milliseconds
                        max_export_batch_size: config.batch_size
                      )
                    else
                      # Sync: SimpleSpanProcessor sends immediately (blocking)
                      OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
                    end

        # Create TracerProvider with processor
        @tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
        @tracer_provider.add_span_processor(processor)

        # Set as global tracer provider
        OpenTelemetry.tracer_provider = @tracer_provider

        mode = config.tracing_async ? "async" : "sync"
        config.logger.info("Langfuse tracing initialized with OpenTelemetry (#{mode} mode)")
      end

      # Shutdown the tracer provider and flush any pending spans
      #
      # @param timeout [Integer] Timeout in seconds
      # @return [void]
      def shutdown(timeout: 30)
        return unless @tracer_provider

        @tracer_provider.shutdown(timeout: timeout)
        @tracer_provider = nil
      end

      # Force flush all pending spans
      #
      # @param timeout [Integer] Timeout in seconds
      # @return [void]
      def force_flush(timeout: 30)
        return unless @tracer_provider

        @tracer_provider.force_flush(timeout: timeout)
      end

      # Check if OTel is initialized
      #
      # @return [Boolean]
      def initialized?
        !@tracer_provider.nil?
      end
    end
  end
end
