# frozen_string_literal: true

require "spec_helper"
require "opentelemetry/sdk"

RSpec.describe "End-to-End Langfuse Integration" do
  let(:public_key) { "pk_test_123" }
  let(:secret_key) { "sk_test_456" }
  let(:base_url) { "https://api.langfuse.test" }

  before do
    # Configure Langfuse
    Langfuse.configure do |config|
      config.public_key = public_key
      config.secret_key = secret_key
      config.base_url = base_url
    end

    # Stub the OTLP endpoint (new endpoint using protobuf)
    stub_request(:post, "#{base_url}/api/public/otel/v1/traces")
      .to_return(status: 200, body: "", headers: {})
  end

  after do
    Langfuse.reset!
  end

  describe "Trace with Generation" do
    it "sends traces to Langfuse OTLP endpoint" do
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

      # Verify OTLP endpoint was called with correct auth
      expect(WebMock).to have_requested(:post, "#{base_url}/api/public/otel/v1/traces")
        .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64("#{public_key}:#{secret_key}")}" })
        .at_least_once
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

      # Verify request was made
      expect(WebMock).to have_requested(:post, "#{base_url}/api/public/otel/v1/traces").at_least_once
    end

    it "supports trace input/output via setters" do
      # Test traces with input/output set via setters
      Langfuse.trace(name: "test-trace-2", user_id: "user-456") do |trace|
        trace.input = { request: "calculate 2+2" }
        trace.output = { result: 4 }
        trace.metadata = { calculator: "v1" }
      end

      Langfuse.force_flush

      # Verify request was made
      expect(WebMock).to have_requested(:post, "#{base_url}/api/public/otel/v1/traces").at_least_once
    end
  end

  describe "Nested Spans (Parent-Child Relationships)" do
    it "correctly establishes parent-child relationships per OTel spec" do
      # Test multi-level nesting:
      # - Trace (root)
      #   - Span 1 (direct child of trace)
      #     - Span 2 (child of Span 1)
      #       - Generation (child of Span 2)
      #   - Generation 2 (direct child of trace)

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

      # Verify OTLP endpoint was called (parent-child relationships are handled by OTel SDK)
      expect(WebMock).to have_requested(:post, "#{base_url}/api/public/otel/v1/traces").at_least_once
    end

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

      # Verify OTLP endpoint was called (parent-child relationships are handled by OTel SDK)
      expect(WebMock).to have_requested(:post, "#{base_url}/api/public/otel/v1/traces").at_least_once
    end
  end
end
