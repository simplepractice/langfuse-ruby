# frozen_string_literal: true

require "spec_helper"
require "opentelemetry/sdk"

RSpec.describe Langfuse::BaseObservation do
  # Test subclass that implements the required #type method
  let(:test_subclass) do
    Class.new(Langfuse::BaseObservation) do
      def type
        "test_observation"
      end
    end
  end

  let(:tracer_provider) { OpenTelemetry::SDK::Trace::TracerProvider.new }
  let(:otel_tracer) { tracer_provider.tracer("test-tracer") }
  let(:otel_span) { otel_tracer.start_span("test-span") }
  let(:observation) { test_subclass.new(otel_span, otel_tracer) }

  describe "#initialize" do
    it "stores otel_span and otel_tracer" do
      expect(observation.otel_span).to eq(otel_span)
      expect(observation.otel_tracer).to eq(otel_tracer)
    end

    it "initializes without attributes" do
      obs = test_subclass.new(otel_span, otel_tracer)
      expect(obs.otel_span).to eq(otel_span)
      expect(obs.otel_tracer).to eq(otel_tracer)
    end

    it "sets initial attributes when provided" do
      attrs = { input: { query: "test" }, output: { result: "success" } }
      obs = test_subclass.new(otel_span, otel_tracer, attributes: attrs)
      span_data = obs.otel_span.to_span_data

      expect(JSON.parse(span_data.attributes["langfuse.observation.input"])).to eq({ "query" => "test" })
      expect(JSON.parse(span_data.attributes["langfuse.observation.output"])).to eq({ "result" => "success" })
    end

    it "handles Types objects" do
      attrs = Langfuse::Types::SpanAttributes.new(
        input: { data: "test" },
        level: "DEFAULT"
      )
      obs = test_subclass.new(otel_span, otel_tracer, attributes: attrs)
      span_data = obs.otel_span.to_span_data

      expect(JSON.parse(span_data.attributes["langfuse.observation.input"])).to eq({ "data" => "test" })
      expect(span_data.attributes["langfuse.observation.level"]).to eq("DEFAULT")
    end
  end

  describe "#id" do
    it "returns hex-encoded span ID" do
      span_id = observation.id
      expect(span_id).to be_a(String)
      expect(span_id.length).to eq(16) # 8 bytes = 16 hex chars
      expect(span_id).to match(/\A[0-9a-f]{16}\z/)
    end

    it "matches the span context span_id" do
      expected_id = otel_span.context.span_id.unpack1("H*")
      expect(observation.id).to eq(expected_id)
    end
  end

  describe "#trace_id" do
    it "returns hex-encoded trace ID" do
      trace_id = observation.trace_id
      expect(trace_id).to be_a(String)
      expect(trace_id.length).to eq(32) # 16 bytes = 32 hex chars
      expect(trace_id).to match(/\A[0-9a-f]{32}\z/)
    end

    it "matches the span context trace_id" do
      expected_id = otel_span.context.trace_id.unpack1("H*")
      expect(observation.trace_id).to eq(expected_id)
    end
  end

  describe "#type" do
    it "returns the type from subclass implementation" do
      expect(observation.type).to eq("test_observation")
    end

    it "raises NotImplementedError if not implemented and not in attributes" do
      abstract_class = Class.new(described_class)
      obs = abstract_class.new(otel_span, otel_tracer)

      expect { obs.type }.to raise_error(NotImplementedError, /Subclass must implement #type/)
    end

    it "reads type from span attributes if not implemented by subclass" do
      # Set type attribute directly on span
      otel_span.set_attribute(Langfuse::OtelAttributes::OBSERVATION_TYPE, "custom_type")
      abstract_class = Class.new(described_class)
      obs = abstract_class.new(otel_span, otel_tracer)

      expect(obs.type).to eq("custom_type")
    end
  end

  describe "#end" do
    it "ends the observation without end_time" do
      expect(otel_span).to receive(:finish).with(end_timestamp: nil)
      observation.end
    end

    it "ends the observation with Time end_time" do
      end_time = Time.now
      expect(otel_span).to receive(:finish).with(end_timestamp: end_time)
      observation.end(end_time: end_time)
    end

    it "ends the observation with Integer timestamp" do
      timestamp = 1_000_000_000_000_000_000 # nanoseconds
      expect(otel_span).to receive(:finish).with(end_timestamp: timestamp)
      observation.end(end_time: timestamp)
    end
  end

  describe "#update_trace" do
    it "updates trace-level attributes" do
      observation.update_trace(
        user_id: "user-123",
        session_id: "session-456",
        tags: %w[production api-v2]
      )

      span_data = otel_span.to_span_data
      expect(span_data.attributes["user.id"]).to eq("user-123")
      expect(span_data.attributes["session.id"]).to eq("session-456")
      tags = JSON.parse(span_data.attributes["langfuse.trace.tags"])
      expect(tags).to eq(%w[production api-v2])
    end

    it "supports method chaining" do
      result = observation.update_trace(user_id: "user-123")
      expect(result).to eq(observation)
    end

    it "handles Types::TraceAttributes objects" do
      attrs = Langfuse::Types::TraceAttributes.new(
        user_id: "user-789",
        metadata: { version: "1.0.0" }
      )
      observation.update_trace(attrs)

      span_data = otel_span.to_span_data
      expect(span_data.attributes["user.id"]).to eq("user-789")
      expect(span_data.attributes["langfuse.trace.metadata.version"]).to eq("1.0.0")
    end
  end

  describe "#start_observation" do
    context "with block (auto-ends)" do
      it "creates a child observation and auto-ends" do
        result = observation.start_observation("child-operation", { input: { step: "processing" } }) do |child|
          expect(child).to be_a(described_class)
          expect(child.type).to eq("span") # Default type
          "block_result"
        end

        expect(result).to eq("block_result")
      end

      it "creates a generation child observation" do
        result = observation.start_observation("llm-call", {
                                                 input: [{ role: "user", content: "Hello" }],
                                                 model: "gpt-4"
                                               }, as_type: :generation) do |child|
          expect(child).to be_a(Langfuse::Generation)
          expect(child.type).to eq("generation")
          "gen_result"
        end

        expect(result).to eq("gen_result")
      end

      it "sets attributes on child observation" do
        observation.start_observation("child", { input: { data: "test" }, level: "ERROR" }) do |child|
          span_data = child.otel_span.to_span_data
          expect(JSON.parse(span_data.attributes["langfuse.observation.input"])).to eq({ "data" => "test" })
          expect(span_data.attributes["langfuse.observation.level"]).to eq("ERROR")
        end
      end
    end

    context "without block (stateful API)" do
      it "creates a child observation and returns it" do
        child = observation.start_observation("child-operation", { input: { step: "processing" } })

        expect(child).to be_a(Langfuse::Span)
        expect(child.type).to eq("span")
      end

      it "creates a generation child observation" do
        child = observation.start_observation("llm-call", {
                                                input: [{ role: "user", content: "Hello" }],
                                                model: "gpt-4"
                                              }, as_type: :generation)

        expect(child).to be_a(Langfuse::Generation)
        expect(child.type).to eq("generation")
      end

      it "requires manual end" do
        child = observation.start_observation("child-operation")
        expect(child.otel_span).to receive(:finish)
        child.end
      end

      it "sets attributes on child observation" do
        child = observation.start_observation("child", { input: { data: "test" }, level: "WARNING" })
        span_data = child.otel_span.to_span_data

        expect(JSON.parse(span_data.attributes["langfuse.observation.input"])).to eq({ "data" => "test" })
        expect(span_data.attributes["langfuse.observation.level"]).to eq("WARNING")
      end

      it "supports different observation types" do
        # NOTE: Only "generation" gets a specialized wrapper (Generation)
        # All other types (span, event, tool, agent) use Span wrapper
        # but the type attribute should still be set correctly on the span
        child = observation.start_observation("test", {}, as_type: :generation)
        span_data = child.otel_span.to_span_data
        expect(span_data.attributes["langfuse.observation.type"]).to eq("generation")

        # For other types, they use Span wrapper which overrides type to "span"
        # The initial type set on the span gets overwritten by Span#type
        # This is expected behavior - Span wrapper always represents "span" type
        child = observation.start_observation("test", {}, as_type: :span)
        span_data = child.otel_span.to_span_data
        expect(span_data.attributes["langfuse.observation.type"]).to eq("span")
      end
    end
  end

  describe "#input=" do
    it "sets input attribute" do
      observation.input = { query: "SELECT * FROM users" }
      span_data = otel_span.to_span_data

      expect(JSON.parse(span_data.attributes["langfuse.observation.input"])).to eq({ "query" => "SELECT * FROM users" })
    end

    it "handles complex nested objects" do
      observation.input = { user: { id: 123, name: "Test" }, tags: %w[a b c] }
      span_data = otel_span.to_span_data

      parsed = JSON.parse(span_data.attributes["langfuse.observation.input"])
      expect(parsed["user"]["id"]).to eq(123)
      expect(parsed["user"]["name"]).to eq("Test")
      expect(parsed["tags"]).to eq(%w[a b c])
    end
  end

  describe "#output=" do
    it "sets output attribute" do
      observation.output = { result: "success", count: 42 }
      span_data = otel_span.to_span_data

      parsed_output = JSON.parse(span_data.attributes["langfuse.observation.output"])
      expect(parsed_output).to eq({ "result" => "success", "count" => 42 })
    end

    it "handles arrays" do
      observation.output = [1, 2, 3, 4, 5]
      span_data = otel_span.to_span_data

      expect(JSON.parse(span_data.attributes["langfuse.observation.output"])).to eq([1, 2, 3, 4, 5])
    end
  end

  describe "#metadata=" do
    it "sets metadata as individual attributes" do
      observation.metadata = { source: "database", cache: "miss" }
      span_data = otel_span.to_span_data

      expect(span_data.attributes["langfuse.observation.metadata.source"]).to eq("database")
      expect(span_data.attributes["langfuse.observation.metadata.cache"]).to eq("miss")
    end

    it "handles nested metadata" do
      observation.metadata = { user: { id: 123, profile: { name: "Test" } } }
      span_data = otel_span.to_span_data

      expect(span_data.attributes["langfuse.observation.metadata.user.id"]).to eq("123")
      expect(span_data.attributes["langfuse.observation.metadata.user.profile.name"]).to eq("Test")
    end
  end

  describe "#level=" do
    it "sets level attribute" do
      observation.level = "WARNING"
      span_data = otel_span.to_span_data

      expect(span_data.attributes["langfuse.observation.level"]).to eq("WARNING")
    end

    it "handles different level values" do
      %w[DEBUG DEFAULT WARNING ERROR].each do |level|
        obs = test_subclass.new(otel_tracer.start_span("test"), otel_tracer)
        obs.level = level
        span_data = obs.otel_span.to_span_data
        expect(span_data.attributes["langfuse.observation.level"]).to eq(level)
      end
    end
  end

  describe "#event" do
    it "adds an event with name only" do
      observation.event(name: "cache-hit")
      events = otel_span.to_span_data.events

      expect(events.length).to eq(1)
      expect(events.first.name).to eq("cache-hit")
    end

    it "adds an event with name and input" do
      observation.event(name: "cache-miss", input: { key: "user:123" })
      events = otel_span.to_span_data.events

      expect(events.length).to eq(1)
      expect(events.first.name).to eq("cache-miss")
      expect(JSON.parse(events.first.attributes["langfuse.observation.input"])).to eq({ "key" => "user:123" })
    end

    it "adds an event with level" do
      observation.event(name: "error-occurred", level: "error")
      events = otel_span.to_span_data.events

      expect(events.length).to eq(1)
      expect(events.first.attributes["langfuse.observation.level"]).to eq("error")
    end

    it "defaults level to 'default'" do
      observation.event(name: "test-event")
      events = otel_span.to_span_data.events

      expect(events.first.attributes["langfuse.observation.level"]).to eq("default")
    end

    it "handles nil input" do
      observation.event(name: "simple-event", input: nil)
      events = otel_span.to_span_data.events

      expect(events.length).to eq(1)
      expect(events.first.attributes).not_to have_key("langfuse.observation.input")
    end
  end

  describe "#current_span" do
    it "returns the underlying OTel span" do
      expect(observation.current_span).to eq(otel_span)
    end
  end

  describe "#update_observation_attributes" do
    it "is protected and called by convenience setters" do
      # This is tested indirectly through the convenience setters
      # We can't directly test protected methods, but we verify they work
      observation.input = { test: "data" }
      span_data = otel_span.to_span_data

      expect(span_data.attributes).to have_key("langfuse.observation.input")
    end
  end

  describe "#normalize_prompt" do
    it "is protected and extracts name/version from prompt objects" do
      # Test indirectly through start_observation with a prompt
      prompt_obj = double(name: "greeting", version: 2)
      child = observation.start_observation("test", { prompt: prompt_obj }, as_type: :generation)
      span_data = child.otel_span.to_span_data

      expect(span_data.attributes["langfuse.observation.prompt.name"]).to eq("greeting")
      expect(span_data.attributes["langfuse.observation.prompt.version"]).to eq(2)
    end

    it "handles hash prompts" do
      prompt_hash = { name: "greeting", version: 3 }
      child = observation.start_observation("test", { prompt: prompt_hash }, as_type: :generation)
      span_data = child.otel_span.to_span_data

      expect(span_data.attributes["langfuse.observation.prompt.name"]).to eq("greeting")
      expect(span_data.attributes["langfuse.observation.prompt.version"]).to eq(3)
    end

    it "handles non-prompt objects" do
      # Objects without name/version methods should pass through
      regular_obj = { some: "data" }
      child = observation.start_observation("test", { prompt: regular_obj }, as_type: :generation)
      span_data = child.otel_span.to_span_data

      # Should not have prompt attributes
      expect(span_data.attributes).not_to have_key("langfuse.observation.prompt.name")
    end
  end

  describe "#create_observation_wrapper" do
    it "creates Generation wrapper for generation type" do
      child = observation.start_observation("test", {}, as_type: :generation)
      expect(child).to be_a(Langfuse::Generation)
    end

    it "creates Span wrapper for span type" do
      child = observation.start_observation("test", {}, as_type: :span)
      expect(child).to be_a(Langfuse::Span)
    end

    it "creates Span wrapper for other types" do
      %w[event tool agent chain].each do |type|
        child = observation.start_observation("test", {}, as_type: type.to_sym)
        expect(child).to be_a(Langfuse::Span)
      end
    end
  end

  describe "hierarchical structure" do
    it "creates nested observations" do
      tracer = Langfuse::Tracer.new(otel_tracer: otel_tracer)
      tracer.trace(name: "parent") do |trace|
        trace.span(name: "level-1") do |span1|
          span1.start_observation("level-2") do |span2|
            span2.start_observation("level-3") do |span3|
              expect(span3).to be_a(described_class)
              expect(span3.trace_id).to eq(trace.trace_id)
            end
          end
        end
      end
    end

    it "shares trace_id across nested observations" do
      tracer = Langfuse::Tracer.new(otel_tracer: otel_tracer)
      trace_id = nil
      tracer.trace(name: "parent") do |trace|
        trace_id = trace.trace_id
        trace.span(name: "child") do |span|
          child = span.start_observation("grandchild")
          expect(child.trace_id).to eq(trace_id)
          child.end
        end
      end
    end
  end

  describe "integration with real OpenTelemetry spans" do
    it "works with actual span lifecycle" do
      tracer = Langfuse::Tracer.new(otel_tracer: otel_tracer)
      span_data = nil

      tracer.trace(name: "test-trace") do |trace|
        child = trace.start_observation("child-operation", { input: { data: "test" } })
        child.output = { result: "success" }
        child.metadata = { source: "api" }
        child.level = "DEFAULT"
        span_data = child.otel_span.to_span_data
        child.end
      end

      expect(span_data.attributes["langfuse.observation.type"]).to eq("span")
      expect(JSON.parse(span_data.attributes["langfuse.observation.input"])).to eq({ "data" => "test" })
      expect(JSON.parse(span_data.attributes["langfuse.observation.output"])).to eq({ "result" => "success" })
      expect(span_data.attributes["langfuse.observation.metadata.source"]).to eq("api")
      expect(span_data.attributes["langfuse.observation.level"]).to eq("DEFAULT")
    end
  end
end
