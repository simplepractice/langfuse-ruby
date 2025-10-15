# frozen_string_literal: true

require "spec_helper"

RSpec.describe Langfuse::IngestionClient do
  let(:public_key) { "pk_test_123" }
  let(:secret_key) { "sk_test_456" }
  let(:base_url) { "https://api.langfuse.test" }
  let(:client) do
    described_class.new(
      public_key: public_key,
      secret_key: secret_key,
      base_url: base_url
    )
  end

  describe "#initialize" do
    it "sets public_key" do
      expect(client.public_key).to eq(public_key)
    end

    it "sets secret_key" do
      expect(client.secret_key).to eq(secret_key)
    end

    it "sets base_url" do
      expect(client.base_url).to eq(base_url)
    end

    it "sets default timeout" do
      expect(client.timeout).to eq(5)
    end

    it "accepts custom timeout" do
      custom_client = described_class.new(
        public_key: public_key,
        secret_key: secret_key,
        timeout: 10
      )
      expect(custom_client.timeout).to eq(10)
    end

    it "creates a default logger when none provided" do
      expect(client.logger).to be_a(Logger)
    end

    it "accepts a custom logger" do
      custom_logger = Logger.new(StringIO.new)
      custom_client = described_class.new(
        public_key: public_key,
        secret_key: secret_key,
        logger: custom_logger
      )
      expect(custom_client.logger).to eq(custom_logger)
    end
  end

  describe "#send_batch" do
    let(:events) do
      [
        {
          id: "event-123",
          timestamp: "2025-10-15T10:00:00.000Z",
          type: "trace-create",
          body: {
            id: "trace-abc",
            name: "test-trace",
            user_id: "user-123"
          }
        },
        {
          id: "event-456",
          timestamp: "2025-10-15T10:00:01.000Z",
          type: "generation-create",
          body: {
            id: "gen-xyz",
            trace_id: "trace-abc",
            name: "llm-call",
            model: "gpt-4"
          }
        }
      ]
    end

    context "with successful response" do
      before do
        stub_request(:post, "#{base_url}/api/public/ingestion")
          .with(
            body: { batch: events }.to_json,
            headers: {
              "Authorization" => /^Basic/,
              "Content-Type" => "application/json"
            }
          )
          .to_return(
            status: 200,
            body: { success: true }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "sends events successfully" do
        expect(client.send_batch(events)).to be(true)
      end

      it "makes a POST request to the correct endpoint" do
        client.send_batch(events)
        expect(WebMock).to have_requested(:post, "#{base_url}/api/public/ingestion")
      end

      it "sends events as JSON batch" do
        client.send_batch(events)
        expect(WebMock).to have_requested(:post, "#{base_url}/api/public/ingestion")
          .with(body: { batch: events }.to_json)
      end
    end

    context "with empty events" do
      it "returns true without making a request" do
        expect(client.send_batch([])).to be(true)
        expect(WebMock).not_to have_requested(:post, "#{base_url}/api/public/ingestion")
      end

      it "handles nil events" do
        expect(client.send_batch(nil)).to be(true)
        expect(WebMock).not_to have_requested(:post, "#{base_url}/api/public/ingestion")
      end
    end

    context "when API returns an error" do
      before do
        stub_request(:post, "#{base_url}/api/public/ingestion")
          .to_return(
            status: 500,
            body: { error: "Internal server error" }.to_json
          )
      end

      it "raises ApiError" do
        expect { client.send_batch(events) }.to raise_error(
          Langfuse::ApiError,
          /Ingestion failed \(500\)/
        )
      end
    end

    context "when network error occurs" do
      before do
        stub_request(:post, "#{base_url}/api/public/ingestion")
          .to_timeout
      end

      it "raises ApiError" do
        expect { client.send_batch(events) }.to raise_error(
          Langfuse::ApiError,
          /Ingestion request failed/
        )
      end

      it "logs the error" do
        logger = instance_double(Logger)
        allow(logger).to receive(:error)

        custom_client = described_class.new(
          public_key: public_key,
          secret_key: secret_key,
          base_url: base_url,
          logger: logger
        )

        expect { custom_client.send_batch(events) }.to raise_error(Langfuse::ApiError)
        expect(logger).to have_received(:error).with(/Langfuse ingestion error/)
      end
    end
  end

  describe "connection configuration" do
    it "includes Authorization header" do
      stub_request(:post, "#{base_url}/api/public/ingestion")
        .to_return(status: 200, body: {}.to_json)

      client.send_batch([{ id: "test" }])

      expect(WebMock).to have_requested(:post, "#{base_url}/api/public/ingestion")
        .with(headers: { "Authorization" => /^Basic/ })
    end

    it "includes Content-Type header" do
      stub_request(:post, "#{base_url}/api/public/ingestion")
        .to_return(status: 200, body: {}.to_json)

      client.send_batch([{ id: "test" }])

      expect(WebMock).to have_requested(:post, "#{base_url}/api/public/ingestion")
        .with(headers: { "Content-Type" => "application/json" })
    end

    it "includes User-Agent header" do
      stub_request(:post, "#{base_url}/api/public/ingestion")
        .to_return(status: 200, body: {}.to_json)

      client.send_batch([{ id: "test" }])

      expect(WebMock).to have_requested(:post, "#{base_url}/api/public/ingestion")
        .with(headers: { "User-Agent" => "langfuse-ruby/#{Langfuse::VERSION}" })
    end
  end

  describe "retry configuration" do
    let(:events) { [{ id: "test" }] }

    it "retries on timeout" do
      stub = stub_request(:post, "#{base_url}/api/public/ingestion")
        .to_timeout.times(2)
        .then
        .to_return(status: 200, body: {}.to_json)

      expect(client.send_batch(events)).to be(true)
      expect(stub).to have_been_requested.times(3)
    end

    it "retries on 503 Service Unavailable" do
      stub = stub_request(:post, "#{base_url}/api/public/ingestion")
        .to_return(status: 503).times(2)
        .then
        .to_return(status: 200, body: {}.to_json)

      expect(client.send_batch(events)).to be(true)
      expect(stub).to have_been_requested.times(3)
    end

    it "retries on 429 Too Many Requests" do
      stub = stub_request(:post, "#{base_url}/api/public/ingestion")
        .to_return(status: 429).times(2)
        .then
        .to_return(status: 200, body: {}.to_json)

      expect(client.send_batch(events)).to be(true)
      expect(stub).to have_been_requested.times(3)
    end

    it "does not retry on 400 Bad Request" do
      stub = stub_request(:post, "#{base_url}/api/public/ingestion")
        .to_return(status: 400, body: { error: "Bad request" }.to_json)

      expect { client.send_batch(events) }.to raise_error(Langfuse::ApiError)
      expect(stub).to have_been_requested.times(1) # No retries
    end

    it "exhausts retries and raises error" do
      stub = stub_request(:post, "#{base_url}/api/public/ingestion")
        .to_return(status: 500).times(4) # More than max retries

      expect { client.send_batch(events) }.to raise_error(Langfuse::ApiError)
      expect(stub).to have_been_requested.times(4) # 1 initial + 3 retries
    end
  end
end
