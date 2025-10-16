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

      # Debug: Print the captured payloads
      puts "\n=== Captured Request Bodies ==="
      captured_request_body.each_with_index do |body, idx|
        puts "\n--- Request #{idx + 1} ---"
        puts JSON.pretty_generate(body)
      end
      puts "=== End Captured Bodies ===\n"

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
      puts "\n=== Generation Event Body ==="
      puts JSON.pretty_generate(generation_event["body"])

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
end
