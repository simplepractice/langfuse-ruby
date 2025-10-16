# frozen_string_literal: true

require "spec_helper"
require "opentelemetry/sdk"

RSpec.describe Langfuse::Exporter do
  let(:public_key) { "pk_test_123" }
  let(:secret_key) { "sk_test_456" }
  let(:base_url) { "https://api.langfuse.test" }
  let(:exporter) do
    described_class.new(
      public_key: public_key,
      secret_key: secret_key,
      base_url: base_url
    )
  end

  # Helper to create a span
  let(:tracer_provider) { OpenTelemetry::SDK::Trace::TracerProvider.new }
  let(:tracer) { tracer_provider.tracer("test-tracer") }

  # Helper to create span data
  def create_span_with_attributes(attributes = {})
    span = nil
    tracer.in_span("test-span", attributes: attributes) do |s|
      span = s
    end
    span.to_span_data
  end

  describe "#initialize" do
    it "creates an ingestion client" do
      expect(exporter.ingestion_client).to be_a(Langfuse::IngestionClient)
    end

    it "passes credentials to ingestion client" do
      expect(exporter.ingestion_client.public_key).to eq(public_key)
      expect(exporter.ingestion_client.secret_key).to eq(secret_key)
    end
  end

  describe "#export" do
    context "with empty span list" do
      it "returns SUCCESS without making requests" do
        result = exporter.export([])
        expect(result).to eq(OpenTelemetry::SDK::Trace::Export::SUCCESS)
      end

      it "handles nil span list" do
        result = exporter.export(nil)
        expect(result).to eq(OpenTelemetry::SDK::Trace::Export::SUCCESS)
      end
    end

    context "with valid spans" do
      let(:span_data) { create_span_with_attributes("langfuse.type" => "span") }

      before do
        stub_request(:post, "#{base_url}/api/public/ingestion")
          .to_return(status: 200, body: {}.to_json)
      end

      it "exports spans successfully" do
        result = exporter.export([span_data])
        expect(result).to eq(OpenTelemetry::SDK::Trace::Export::SUCCESS)
      end

      it "sends events to ingestion API" do
        exporter.export([span_data])
        expect(WebMock).to have_requested(:post, "#{base_url}/api/public/ingestion")
      end
    end

    context "with ingestion failure" do
      let(:span_data) { create_span_with_attributes }

      before do
        stub_request(:post, "#{base_url}/api/public/ingestion")
          .to_return(status: 500, body: { error: "Server error" }.to_json)
      end

      it "returns FAILURE on error" do
        result = exporter.export([span_data])
        expect(result).to eq(OpenTelemetry::SDK::Trace::Export::FAILURE)
      end

      it "does not raise exception" do
        expect { exporter.export([span_data]) }.not_to raise_error
      end
    end
  end

  describe "#force_flush" do
    it "returns SUCCESS" do
      result = exporter.force_flush
      expect(result).to eq(OpenTelemetry::SDK::Trace::Export::SUCCESS)
    end
  end

  describe "#shutdown" do
    it "returns SUCCESS" do
      result = exporter.shutdown
      expect(result).to eq(OpenTelemetry::SDK::Trace::Export::SUCCESS)
    end
  end

  describe "span conversion to events" do
    before do
      stub_request(:post, "#{base_url}/api/public/ingestion")
        .to_return(status: 200, body: {}.to_json)
    end

    it "converts trace-create event" do
      span_data = create_span_with_attributes(
        "langfuse.type" => "trace",
        "langfuse.user_id" => "user-123"
      )

      exporter.export([span_data])

      expect(WebMock).to have_requested(:post, "#{base_url}/api/public/ingestion").once
    end

    it "converts span-create event" do
      span_data = create_span_with_attributes(
        "langfuse.type" => "span"
      )

      exporter.export([span_data])

      expect(WebMock).to have_requested(:post, "#{base_url}/api/public/ingestion").once
    end

    it "converts generation-create event" do
      span_data = create_span_with_attributes(
        "langfuse.type" => "generation",
        "langfuse.model" => "gpt-4"
      )

      exporter.export([span_data])

      expect(WebMock).to have_requested(:post, "#{base_url}/api/public/ingestion").once
    end

    it "exports multiple spans in batch" do
      span1 = create_span_with_attributes("langfuse.type" => "trace")
      span2 = create_span_with_attributes("langfuse.type" => "span")

      exporter.export([span1, span2])

      expect(WebMock).to have_requested(:post, "#{base_url}/api/public/ingestion").once
    end

    it "defaults to span-create when no type specified" do
      span_data = create_span_with_attributes({})

      exporter.export([span_data])

      expect(WebMock).to have_requested(:post, "#{base_url}/api/public/ingestion").once
    end

    # rubocop:disable RSpec/MultipleExpectations
    it "properly parses input, output, and usage for generation" do
      input_data = { "messages" => [{ "role" => "user", "content" => "Hello" }] }
      output_data = { "role" => "assistant", "content" => "Hi there!" }
      usage_data = { "prompt_tokens" => 10, "completion_tokens" => 20, "total_tokens" => 30 }

      span_data = create_span_with_attributes(
        "langfuse.type" => "generation",
        "langfuse.model" => "gpt-4",
        "langfuse.input" => input_data.to_json,
        "langfuse.output" => output_data.to_json,
        "langfuse.usage" => usage_data.to_json
      )

      # Capture the request body
      request_body = nil
      stub_request(:post, "#{base_url}/api/public/ingestion")
        .to_return do |request|
          request_body = JSON.parse(request.body)
          { status: 200, body: {}.to_json }
        end

      exporter.export([span_data])

      # Verify the event was sent
      expect(WebMock).to have_requested(:post, "#{base_url}/api/public/ingestion").once

      # Verify the parsed data
      event = request_body["batch"].first
      expect(event["type"]).to eq("generation-create")
      expect(event["body"]["input"]).to eq(input_data)
      expect(event["body"]["output"]).to eq(output_data)
      expect(event["body"]["usage"]).to eq(usage_data)
      expect(event["body"]["model"]).to eq("gpt-4")
    end
    # rubocop:enable RSpec/MultipleExpectations

    it "properly parses input and output for span" do
      input_data = { "query" => "SELECT * FROM users" }
      output_data = { "results" => [{ "id" => 1, "name" => "Alice" }], "count" => 1 }

      span_data = create_span_with_attributes(
        "langfuse.type" => "span",
        "langfuse.input" => input_data.to_json,
        "langfuse.output" => output_data.to_json
      )

      # Capture the request body
      request_body = nil
      stub_request(:post, "#{base_url}/api/public/ingestion")
        .to_return do |request|
          request_body = JSON.parse(request.body)
          { status: 200, body: {}.to_json }
        end

      exporter.export([span_data])

      # Verify the parsed data
      event = request_body["batch"].first
      expect(event["type"]).to eq("span-create")
      expect(event["body"]["input"]).to eq(input_data)
      expect(event["body"]["output"]).to eq(output_data)
    end
  end
end
