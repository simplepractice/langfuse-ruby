# frozen_string_literal: true

require "spec_helper"
require "opentelemetry/sdk"

RSpec.describe "End-to-End Langfuse Integration" do
  let(:public_key) { "pk_test_123" }
  let(:secret_key) { "sk_test_456" }
  let(:base_url) { "https://api.langfuse.test" }

  # Capture the actual request body sent to Langfuse
  let(:captured_request_body) { [] }

  before do
    # Configure Langfuse with tracing enabled
    Langfuse.configure do |config|
      config.public_key = public_key
      config.secret_key = secret_key
      config.base_url = base_url
      config.tracing_enabled = true
    end

    # Stub the ingestion API and capture request body
    stub_request(:post, "#{base_url}/api/public/ingestion")
      .to_return do |request|
        captured_request_body << JSON.parse(request.body)
        { status: 200, body: {}.to_json }
      end
  end

  after do
    Langfuse.reset!
  end

  describe "Trace with Generation" do
    # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    it "sends correct payload to Langfuse API" do
      # Simulate the spam-detection script
      Langfuse.trace(name: "spam-detection", user_id: "test-user") do |trace|
        messages = [
          { role: :system, content: "You are a spam detector" },
          { role: :user, content: "Buy meds!" }
        ]

        trace.generation(
          name: "classify",
          model: "gpt-4",
          input: messages
        ) do |gen|
          gen.output = "95"
          gen.usage = {
            prompt_tokens: 50,
            completion_tokens: 2,
            total_tokens: 52
          }
        end
      end

      # Force flush to send the data
      Langfuse.force_flush

      # Verify request was made
      expect(WebMock).to have_requested(:post, "#{base_url}/api/public/ingestion").at_least_once

      # Verify the payloads
      all_events = captured_request_body.flat_map { |req| req["batch"] }

      # Should have 2 events: trace-create and generation-create
      expect(all_events.length).to be >= 2

      trace_event = all_events.find { |e| e["type"] == "trace-create" }
      generation_event = all_events.find { |e| e["type"] == "generation-create" }

      expect(trace_event).not_to be_nil
      expect(generation_event).not_to be_nil

      # Verify trace data
      expect(trace_event["body"]["name"]).to eq("spam-detection")
      expect(trace_event["body"]["user_id"]).to eq("test-user")

      # Verify generation data
      expect(generation_event["body"]["name"]).to eq("classify")
      expect(generation_event["body"]["model"]).to eq("gpt-4")

      # THIS IS THE KEY TEST: Check if input/output are present and parsed correctly
      # Input should be the messages array (parsed from JSON)
      expect(generation_event["body"]["input"]).to eq([
                                                        { "role" => "system", "content" => "You are a spam detector" },
                                                        { "role" => "user", "content" => "Buy meds!" }
                                                      ])

      # Output should be the string "95" (parsed from JSON)
      expect(generation_event["body"]["output"]).to eq("95")

      # Usage should be the hash (parsed from JSON)
      expect(generation_event["body"]["usage"]).to eq({
                                                        "prompt_tokens" => 50,
                                                        "completion_tokens" => 2,
                                                        "total_tokens" => 52
                                                      })
    end
    # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations

    it "supports trace input/output via parameters" do
      # Test traces with input/output passed as parameters
      Langfuse.trace(
        name: "test-trace",
        user_id: "user-123",
        input: { query: "What is Ruby?" },
        output: { answer: "A programming language" },
        metadata: { foo: "bar" }
      ) do |trace|
        trace.span(name: "step-1", input: { query: "test" }) do |span|
          span.output = { result: "success" }
        end
      end

      Langfuse.force_flush

      all_events = captured_request_body.flat_map { |req| req["batch"] }

      trace_event = all_events.find { |e| e["type"] == "trace-create" }
      span_event = all_events.find { |e| e["type"] == "span-create" }

      # Trace should have input/output
      expect(trace_event["body"]["input"]).to eq({ "query" => "What is Ruby?" })
      expect(trace_event["body"]["output"]).to eq({ "answer" => "A programming language" })
      expect(trace_event["body"]["metadata"]).to eq({ "foo" => "bar" })

      # Span should have input/output
      expect(span_event["body"]["input"]).to eq({ "query" => "test" })
      expect(span_event["body"]["output"]).to eq({ "result" => "success" })
    end

    it "supports trace input/output via setters" do
      # Test traces with input/output set via setters
      Langfuse.trace(name: "test-trace-2", user_id: "user-456") do |trace|
        trace.input = { request: "calculate 2+2" }
        trace.output = { result: 4 }
        trace.metadata = { calculator: "v1" }
      end

      Langfuse.force_flush

      all_events = captured_request_body.flat_map { |req| req["batch"] }

      trace_event = all_events.find { |e| e["type"] == "trace-create" && e["body"]["name"] == "test-trace-2" }

      # Trace should have input/output set via setters
      expect(trace_event["body"]["input"]).to eq({ "request" => "calculate 2+2" })
      expect(trace_event["body"]["output"]).to eq({ "result" => 4 })
      expect(trace_event["body"]["metadata"]).to eq({ "calculator" => "v1" })
    end
  end

  describe "Nested Spans (Parent-Child Relationships)" do
    # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    it "correctly establishes parent-child relationships per OTel spec" do
      # Test multi-level nesting:
      # - Trace (root)
      #   - Span 1 (direct child of trace) - should have NO parent_observation_id
      #     - Span 2 (child of Span 1) - should have parent_observation_id = Span 1's ID
      #       - Generation (child of Span 2) - should have parent_observation_id = Span 2's ID
      #   - Generation 2 (direct child of trace) - should have NO parent_observation_id

      Langfuse.trace(
        name: "nested-test",
        user_id: "user-789",
        input: { query: "test nested spans" }
      ) do |trace|
        trace.span(name: "span-1", input: { step: 1 }) do |span1|
          span1.span(name: "span-2", input: { step: 2 }) do |span2|
            span2.generation(
              name: "gen-nested",
              model: "gpt-4",
              input: "nested generation"
            ) do |gen|
              gen.output = "nested result"
              gen.usage = { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
            end
            span2.output = { step2: "done" }
          end
          span1.output = { step1: "done" }
        end

        trace.generation(
          name: "gen-direct",
          model: "gpt-4",
          input: "direct generation"
        ) do |gen|
          gen.output = "direct result"
          gen.usage = { prompt_tokens: 5, completion_tokens: 3, total_tokens: 8 }
        end

        trace.output = { status: "completed" }
      end

      Langfuse.force_flush

      # Collect all events
      all_events = captured_request_body.flat_map { |req| req["batch"] }

      # Find specific events
      trace_event = all_events.find { |e| e["type"] == "trace-create" && e["body"]["name"] == "nested-test" }
      span1_event = all_events.find { |e| e["type"] == "span-create" && e["body"]["name"] == "span-1" }
      span2_event = all_events.find { |e| e["type"] == "span-create" && e["body"]["name"] == "span-2" }
      gen_nested_event = all_events.find do |e|
        e["type"] == "generation-create" && e["body"]["name"] == "gen-nested"
      end
      gen_direct_event = all_events.find do |e|
        e["type"] == "generation-create" && e["body"]["name"] == "gen-direct"
      end

      # Verify all events exist
      expect(trace_event).not_to be_nil, "trace-create event not found"
      expect(span1_event).not_to be_nil, "span-1 event not found"
      expect(span2_event).not_to be_nil, "span-2 event not found"
      expect(gen_nested_event).not_to be_nil, "gen-nested event not found"
      expect(gen_direct_event).not_to be_nil, "gen-direct event not found"

      # Get IDs for comparison
      trace_id = trace_event["body"]["id"]
      span1_id = span1_event["body"]["id"]
      span2_id = span2_event["body"]["id"]

      # KEY ASSERTIONS: Verify parent-child relationships per Langfuse/OTel spec

      # 1. All observations should reference the same trace_id
      expect(span1_event["body"]["trace_id"]).to eq(trace_id)
      expect(span2_event["body"]["trace_id"]).to eq(trace_id)
      expect(gen_nested_event["body"]["trace_id"]).to eq(trace_id)
      expect(gen_direct_event["body"]["trace_id"]).to eq(trace_id)

      # 2. Direct children of trace should NOT have parent_observation_id
      expect(span1_event["body"]).not_to have_key("parent_observation_id"),
                                         "span-1 (direct child of trace) should not have parent_observation_id"
      expect(gen_direct_event["body"]).not_to have_key("parent_observation_id"),
                                              "gen-direct (direct child of trace) should not have parent_observation_id"

      # 3. span-2 should have parent_observation_id = span-1's ID
      expect(span2_event["body"]["parent_observation_id"]).to eq(span1_id),
                                                              "span-2 should have parent_observation_id = span-1's ID"

      # 4. gen-nested should have parent_observation_id = span-2's ID
      expect(gen_nested_event["body"]["parent_observation_id"]).to eq(span2_id),
                                                                   "gen-nested should have parent = span-2 ID"
    end
    # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations

    it "handles multiple parallel branches correctly" do
      # Test parallel branches:
      # - Trace
      #   - Branch 1 (span)
      #     - Nested 1 (span)
      #   - Branch 2 (span)
      #     - Nested 2 (span)

      Langfuse.trace(name: "parallel-branches") do |trace|
        trace.span(name: "branch-1") do |branch1|
          branch1.span(name: "nested-1") do |nested1|
            nested1.output = { result: 1 }
          end
        end

        trace.span(name: "branch-2") do |branch2|
          branch2.span(name: "nested-2") do |nested2|
            nested2.output = { result: 2 }
          end
        end
      end

      Langfuse.force_flush

      all_events = captured_request_body.flat_map { |req| req["batch"] }

      branch1 = all_events.find { |e| e["type"] == "span-create" && e["body"]["name"] == "branch-1" }
      branch2 = all_events.find { |e| e["type"] == "span-create" && e["body"]["name"] == "branch-2" }
      nested1 = all_events.find { |e| e["type"] == "span-create" && e["body"]["name"] == "nested-1" }
      nested2 = all_events.find { |e| e["type"] == "span-create" && e["body"]["name"] == "nested-2" }

      # Both branches should be direct children of trace (no parent_observation_id)
      expect(branch1["body"]).not_to have_key("parent_observation_id")
      expect(branch2["body"]).not_to have_key("parent_observation_id")

      # Nested spans should reference their respective parent branches
      expect(nested1["body"]["parent_observation_id"]).to eq(branch1["body"]["id"])
      expect(nested2["body"]["parent_observation_id"]).to eq(branch2["body"]["id"])
    end
  end
end
