# frozen_string_literal: true

require "spec_helper"
require "opentelemetry/sdk"

RSpec.describe "OpenTelemetry Integration" do
  let(:tracer_provider) { OpenTelemetry::SDK::Trace::TracerProvider.new }
  let(:tracer) { tracer_provider.tracer("langfuse-test") }

  describe "basic OTel functionality" do
    it "can create a tracer" do
      expect(tracer).to be_a(OpenTelemetry::SDK::Trace::Tracer)
    end

    it "can create a simple span" do
      span = nil

      tracer.in_span("test-span") do |current_span|
        span = current_span
        expect(current_span).to be_a(OpenTelemetry::SDK::Trace::Span)
        expect(current_span.name).to eq("test-span")
      end

      # Verify span completed
      expect(span).not_to be_nil
      expect(span.recording?).to be(false) # Span should be ended
    end

    it "can add attributes to spans" do
      attributes = nil

      tracer.in_span("attributed-span", attributes: { "test.key" => "test-value" }) do |span|
        span.set_attribute("custom.attribute", "custom-value")
        attributes = span.to_span_data.attributes
      end

      expect(attributes).to include(
        "test.key" => "test-value",
        "custom.attribute" => "custom-value"
      )
    end

    it "can create nested spans" do
      parent_span = nil
      child_span = nil

      tracer.in_span("parent-span") do |parent|
        parent_span = parent

        tracer.in_span("child-span") do |child|
          child_span = child

          # Child should have parent's span_id as its parent_span_id
          parent_span_id = parent.context.span_id
          child_parent_id = child.to_span_data.parent_span_id

          expect(child_parent_id).to eq(parent_span_id)
        end
      end

      expect(parent_span).not_to be_nil
      expect(child_span).not_to be_nil
    end

    it "can capture span events" do
      events = nil

      tracer.in_span("event-span") do |span|
        span.add_event("test-event", attributes: { "event.data" => "test" })
        events = span.to_span_data.events
      end

      expect(events).not_to be_empty
      expect(events.first.name).to eq("test-event")
      expect(events.first.attributes).to include("event.data" => "test")
    end
  end

  describe "span data extraction" do
    it "captures start and end timestamps" do
      span_ref = nil

      tracer.in_span("timed-span") do |span|
        span_ref = span
        sleep 0.01 # Small delay to ensure different timestamps
      end

      # Access span_data after span has ended
      span_data = span_ref.to_span_data
      expect(span_data.start_timestamp).to be > 0
      expect(span_data.end_timestamp).to be > 0
      expect(span_data.end_timestamp).to be > span_data.start_timestamp
    end

    it "captures trace and span IDs" do
      span_ref = nil

      tracer.in_span("id-span") do |span|
        span_ref = span
      end

      # Access span_data after span has ended
      span_data = span_ref.to_span_data

      # Convert binary IDs to hex strings
      trace_id_hex = span_data.trace_id.unpack1("H*")
      span_id_hex = span_data.span_id.unpack1("H*")

      expect(trace_id_hex).to match(/\A[0-9a-f]{32}\z/)
      expect(span_id_hex).to match(/\A[0-9a-f]{16}\z/)
    end
  end

  describe "context propagation" do
    it "maintains context within nested blocks" do
      outer_context = nil
      inner_context = nil

      tracer.in_span("outer") do |_outer_span|
        outer_context = OpenTelemetry::Context.current

        tracer.in_span("inner") do |_inner_span|
          inner_context = OpenTelemetry::Context.current

          # Inner context should be different from outer
          expect(inner_context).not_to eq(outer_context)

          # But inner span should reference outer trace
          outer_span_context = OpenTelemetry::Trace.current_span(outer_context).context
          inner_span_context = OpenTelemetry::Trace.current_span(inner_context).context

          expect(inner_span_context.trace_id).to eq(outer_span_context.trace_id)
        end
      end
    end
  end
end
