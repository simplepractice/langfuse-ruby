# frozen_string_literal: true

module Langfuse
  # Base class for all Langfuse observation wrappers providing unified functionality.
  #
  # This abstract class serves as the foundation for all observation types in Langfuse,
  # encapsulating common operations and properties shared across spans, generations,
  # events, and specialized observation types like agents, tools, and chains.
  #
  # ## Core Capabilities
  # - **OpenTelemetry Integration**: Wraps OTEL spans with Langfuse-specific functionality
  # - **Unique Identification**: Provides span ID and trace ID for correlation
  # - **Lifecycle Management**: Handles observation creation, updates, and completion
  # - **Trace Context**: Enables updating trace-level attributes from any observation
  # - **Hierarchical Structure**: Supports creating nested child observations
  #
  # ## Common Properties
  # - `id`: Unique identifier for this observation (OpenTelemetry span ID as hex string)
  # - `trace_id`: Identifier of the parent trace containing this observation (hex string)
  # - `otel_span`: Direct access to the underlying OpenTelemetry span
  # - `otel_tracer`: Direct access to the underlying OpenTelemetry tracer
  # - `type`: The observation type (span, generation, event, etc.)
  #
  # ## Common Methods
  # - `end(end_time: nil)`: Marks the observation as complete with optional timestamp
  # - `update(attrs)`: Updates observation-level attributes
  # - `update_trace(attrs)`: Sets trace-level attributes like user ID, session ID, tags
  # - `start_observation(name, attrs = {}, as_type: :span)`: Creates child observations
  #
  # @example
  #   # All observation types share these common capabilities
  #   observation = Langfuse::Span.new(otel_span, otel_tracer)
  #
  #   # Common properties available on all observations
  #   puts "Observation ID: #{observation.id}"
  #   puts "Trace ID: #{observation.trace_id}"
  #   puts "Type: #{observation.type}"
  #
  #   # Common methods available on all observations
  #   observation.update_trace(
  #     user_id: "user-123",
  #     session_id: "session-456",
  #     tags: ["production", "api-v2"]
  #   )
  #
  #   # Create child observations
  #   child = observation.start_observation("child-operation", {
  #     input: { step: "processing" }
  #   })
  #
  #   # End observations
  #   child.end
  #   observation.end
  #
  # @abstract Subclass and implement {#type} to create concrete observation types
  class BaseObservation
    attr_reader :otel_span, :otel_tracer

    # Initialize a new BaseObservation wrapper
    #
    # @param otel_span [OpenTelemetry::SDK::Trace::Span] The underlying OTel span
    # @param otel_tracer [OpenTelemetry::SDK::Trace::Tracer] The OTel tracer
    # @param attributes [Hash, Types::SpanAttributes, Types::GenerationAttributes, nil] Optional initial attributes
    def initialize(otel_span, otel_tracer, attributes: nil)
      @otel_span = otel_span
      @otel_tracer = otel_tracer

      # Set initial attributes if provided
      return unless attributes

      # Subclasses override #type to return a hardcoded string, so calling it here is safe
      # It doesn't read from span attributes, avoiding the initialization order issue
      update_observation_attributes(attributes.to_h)
    end

    # Gets the unique span ID from the OpenTelemetry span context
    #
    # @return [String] Hex-encoded span ID (16 hex characters)
    def id
      @otel_span.context.span_id.unpack1("H*")
    end

    # Gets the trace ID from the OpenTelemetry span context
    #
    # @return [String] Hex-encoded trace ID (32 hex characters)
    def trace_id
      @otel_span.context.trace_id.unpack1("H*")
    end

    # Gets the observation type
    #
    # Must be implemented by subclasses or read from span attributes
    #
    # @return [String] Observation type (e.g., "span", "generation", "event")
    def type
      @otel_span.attributes[OtelAttributes::OBSERVATION_TYPE] || raise(NotImplementedError,
                                                                       "Subclass must implement #type")
    end

    # Ends the observation, marking it as complete
    #
    # @param end_time [Time, Integer, nil] Optional end time (Time object or Unix timestamp in nanoseconds)
    # @return [void]
    #
    # @example
    #   observation.end
    #   observation.end(end_time: Time.now)
    def end(end_time: nil)
      @otel_span.finish(end_timestamp: end_time)
    end

    # Updates the parent trace with new attributes
    #
    # This allows any observation to update trace-level attributes like user_id,
    # session_id, tags, etc. These attributes apply to the entire trace, not
    # just this observation.
    #
    # @param attrs [Hash, Types::TraceAttributes] Trace attributes to set
    # @return [self] Returns self for method chaining
    #
    # @example
    #   observation.update_trace(
    #     user_id: "user-123",
    #     session_id: "session-456",
    #     tags: ["production", "api-v2"],
    #     metadata: { version: "2.1.0" }
    #   )
    def update_trace(attrs)
      otel_attrs = OtelAttributes.create_trace_attributes(attrs.to_h)
      otel_attrs.each { |key, value| @otel_span.set_attribute(key, value) }
      self
    end

    # Creates a new child observation within this observation's context
    #
    # This method enables hierarchical tracing by creating child observations that inherit
    # the parent's trace context. It supports all observation types with automatic type
    # handling based on the `as_type` parameter.
    #
    # Supports both block-based (auto-ends) and stateful (manual end) APIs:
    # - If a block is given, the observation auto-ends when the block completes
    # - If no block is given, returns the observation object and requires manual `.end`
    #
    # @param name [String] Descriptive name for the child observation
    # @param attrs [Hash, Types::SpanAttributes, Types::GenerationAttributes, nil] Observation attributes
    # @param as_type [Symbol, String] Observation type (:span, :generation, :event, etc.)
    # @yield [observation] Optional block that receives the observation object
    # @yieldparam observation [BaseObservation] The child observation object
    # @return [BaseObservation, Object] The child observation (or block return value if block given)
    #
    # @example Block-based API (auto-ends)
    #   observation.start_observation("nested-operation") do |child|
    #     result = perform_operation
    #     child.update(output: result)
    #   end
    #
    # @example Stateful API (manual end)
    #   child_span = observation.start_observation("data-processing", {
    #     input: { userId: "123", dataSize: 1024 }
    #   })
    #   result = process_data
    #   child_span.output = result
    #   child_span.end
    #
    # @example Create child generation
    #   child_gen = observation.start_observation("llm-call", {
    #     input: [{ role: "user", content: "Hello" }],
    #     model: "gpt-4"
    #   }, as_type: :generation)
    def start_observation(name, attrs = {}, as_type: :span, &block)
      type_str = as_type.to_s

      # Build attributes using OtelAttributes helper
      otel_attrs = OtelAttributes.create_observation_attributes(type_str, attrs.to_h)

      if block
        # Block-based API: auto-ends when block completes
        # Returns the block's return value
        @otel_tracer.in_span(name, attributes: otel_attrs) do |child_otel_span|
          # Attributes already set on span, no need to pass to constructor
          observation_obj = create_observation_wrapper(type_str, child_otel_span, @otel_tracer, attributes: nil)
          block.call(observation_obj)
        end
      else
        # Stateful API: manual end required
        child_otel_span = @otel_tracer.start_span(name, attributes: otel_attrs)
        # Attributes already set on span, no need to pass to constructor
        create_observation_wrapper(type_str, child_otel_span, @otel_tracer, attributes: nil)
      end
    end

    # Convenience setter for input
    #
    # Sets observation-level input attributes. Note that Trace overrides this
    # method to set trace-level attributes instead (see Trace#input=).
    #
    # @param value [Object] Input value (will be JSON-encoded)
    # @return [void]
    #
    # @example
    #   observation.input = { query: "SELECT * FROM users" }
    def input=(value)
      update_observation_attributes(input: value)
    end

    # Convenience setter for output
    #
    # Sets observation-level output attributes. Note that Trace overrides this
    # method to set trace-level attributes instead (see Trace#output=).
    #
    # @param value [Object] Output value (will be JSON-encoded)
    # @return [void]
    #
    # @example
    #   observation.output = { result: "success", count: 42 }
    def output=(value)
      update_observation_attributes(output: value)
    end

    # Convenience setter for metadata
    #
    # @param value [Hash] Metadata hash (expanded into individual langfuse.observation.metadata.* attributes)
    # @return [void]
    #
    # @example
    #   observation.metadata = { source: "database", cache: "miss" }
    def metadata=(value)
      update_observation_attributes(metadata: value)
    end

    # Convenience setter for level
    #
    # @param value [String] Level (DEBUG, DEFAULT, WARNING, ERROR)
    # @return [void]
    #
    # @example
    #   observation.level = "WARNING"
    def level=(value)
      update_observation_attributes(level: value)
    end

    # Add an event to the observation
    #
    # @param name [String] Event name
    # @param input [Object, nil] Optional event data
    # @param level [String] Log level (debug, default, warning, error)
    # @return [void]
    #
    # @example
    #   observation.event(name: "cache-hit", input: { key: "user:123" })
    #   observation.event(name: "streaming-started")
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

    # Updates observation-level attributes
    #
    # This is a protected method used by subclasses' public `update` methods.
    # Subclasses should implement their own `update` method that calls this.
    #
    # @param attrs [Hash, Types::SpanAttributes, Types::GenerationAttributes] Attributes to update
    # @return [void]
    #
    # @example
    #   # Called internally by subclass update methods
    #   update_observation_attributes({ output: { result: "success" }, level: "DEFAULT" })
    #
    # @api private
    protected

    def update_observation_attributes(attrs = {}, **kwargs)
      # Merge keyword arguments into attrs hash
      attrs_hash = if kwargs.any?
                     attrs.to_h.merge(kwargs)
                   else
                     attrs.to_h
                   end

      # Subclasses always override #type to return a hardcoded string
      # This avoids reading from span attributes which might not be set yet
      otel_attrs = OtelAttributes.create_observation_attributes(type, attrs_hash)
      otel_attrs.each { |key, value| @otel_span.set_attribute(key, value) }
    end

    # Converts a prompt object to hash format for OtelAttributes
    #
    # If the prompt object responds to both :name and :version methods,
    # extracts them into a hash. Otherwise, returns the prompt as-is.
    #
    # @param prompt [Object, Hash, nil] Prompt object or hash
    # @return [Hash, Object, nil] Hash with name and version, or original prompt
    #
    # @api protected
    def normalize_prompt(prompt)
      case prompt
      in obj if obj.respond_to?(:name) && obj.respond_to?(:version)
        { name: obj.name, version: obj.version }
      else
        prompt
      end
    end

    private

    # Creates the appropriate observation wrapper based on type
    #
    # Currently supports specialized wrappers for "generation" type.
    # All other types (including "span", "event", etc.) use the Span wrapper.
    #
    # @param type_str [String] Observation type string
    # @param otel_span [OpenTelemetry::SDK::Trace::Span] The OTel span
    # @param otel_tracer [OpenTelemetry::SDK::Trace::Tracer] The OTel tracer
    # @param attributes [Hash, nil] Optional attributes
    # @return [BaseObservation] Appropriate observation wrapper instance (Generation or Span)
    def create_observation_wrapper(type_str, otel_span, otel_tracer, attributes: nil)
      case type_str
      when "generation"
        Generation.new(otel_span, otel_tracer, attributes: attributes)
      else
        # Default to Span for "span" and all other types (event, tool, etc.)
        Span.new(otel_span, otel_tracer, attributes: attributes)
      end
    end
  end
end
