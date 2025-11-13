# frozen_string_literal: true

require "spec_helper"

RSpec.describe Langfuse::ApiClient do
  let(:public_key) { "pk_test" }
  let(:secret_key) { "sk_test" }
  let(:base_url) { "https://api.langfuse.com" }
  let(:logger) { Logger.new($stdout, level: Logger::WARN) }

  let(:prompt_data) do
    {
      "id" => "prompt123",
      "name" => "greeting",
      "version" => 1,
      "type" => "text",
      "prompt" => "Hello {{name}}!",
      "labels" => ["production"],
      "tags" => ["customer-facing"],
      "config" => {}
    }
  end

  describe "SWR caching integration" do
    context "with SWR-enabled cache" do
      let(:swr_cache) { instance_double("Langfuse::RailsCacheAdapter") }
      let(:api_client) do
        described_class.new(
          public_key: public_key,
          secret_key: secret_key,
          base_url: base_url,
          logger: logger,
          cache: swr_cache
        )
      end

      before do
        # Mock SWR cache methods
        allow(swr_cache).to receive(:respond_to?)
          .with(:fetch_with_stale_while_revalidate)
          .and_return(true)
      end

      it "uses SWR fetch method when available" do
        cache_key = "greeting:version:1"

        expect(Langfuse::PromptCache).to receive(:build_key)
          .with("greeting", version: 1, label: nil)
          .and_return(cache_key)

        expect(swr_cache).to receive(:fetch_with_stale_while_revalidate)
          .with(cache_key)
          .and_yield
          .and_return(prompt_data)

        # Mock the API call that would happen in the block
        expect(api_client).to receive(:fetch_prompt_from_api)
          .with("greeting", version: 1, label: nil)
          .and_return(prompt_data)

        result = api_client.get_prompt("greeting", version: 1)
        expect(result).to eq(prompt_data)
      end

      it "handles cache miss with SWR" do
        cache_key = "greeting:latest"

        expect(Langfuse::PromptCache).to receive(:build_key)
          .with("greeting", version: nil, label: nil)
          .and_return(cache_key)

        expect(swr_cache).to receive(:fetch_with_stale_while_revalidate)
          .with(cache_key)
          .and_yield
          .and_return(prompt_data)

        # Mock the actual API call
        connection = instance_double("Faraday::Connection")
        response = instance_double("Faraday::Response", status: 200, body: prompt_data.to_json)

        allow(api_client).to receive(:connection).and_return(connection)
        allow(connection).to receive(:get).and_return(response)
        allow(api_client).to receive(:handle_response).with(response).and_return(prompt_data)

        result = api_client.get_prompt("greeting")
        expect(result).to eq(prompt_data)
      end

      it "passes through all prompt parameters to cache key building" do
        expect(Langfuse::PromptCache).to receive(:build_key)
          .with("support-bot", version: nil, label: "staging")
          .and_return("support-bot:label:staging")

        expect(swr_cache).to receive(:fetch_with_stale_while_revalidate)
          .with("support-bot:label:staging")
          .and_return(prompt_data)

        api_client.get_prompt("support-bot", label: "staging")
      end
    end

    context "with stampede protection cache (no SWR)" do
      let(:stampede_cache) { instance_double("Langfuse::RailsCacheAdapter") }
      let(:api_client) do
        described_class.new(
          public_key: public_key,
          secret_key: secret_key,
          base_url: base_url,
          logger: logger,
          cache: stampede_cache
        )
      end

      before do
        allow(stampede_cache).to receive(:respond_to?)
          .with(:fetch_with_stale_while_revalidate)
          .and_return(false)
        allow(stampede_cache).to receive(:respond_to?)
          .with(:fetch_with_lock)
          .and_return(true)
      end

      it "falls back to stampede protection when SWR not available" do
        cache_key = "greeting:version:1"

        expect(Langfuse::PromptCache).to receive(:build_key)
          .with("greeting", version: 1, label: nil)
          .and_return(cache_key)

        expect(stampede_cache).to receive(:fetch_with_lock)
          .with(cache_key)
          .and_yield
          .and_return(prompt_data)

        expect(api_client).to receive(:fetch_prompt_from_api)
          .with("greeting", version: 1, label: nil)
          .and_return(prompt_data)

        result = api_client.get_prompt("greeting", version: 1)
        expect(result).to eq(prompt_data)
      end
    end

    context "with simple cache (no SWR, no stampede protection)" do
      let(:simple_cache) { instance_double("Langfuse::PromptCache") }
      let(:api_client) do
        described_class.new(
          public_key: public_key,
          secret_key: secret_key,
          base_url: base_url,
          logger: logger,
          cache: simple_cache
        )
      end

      before do
        allow(simple_cache).to receive(:respond_to?)
          .with(:fetch_with_stale_while_revalidate)
          .and_return(false)
        allow(simple_cache).to receive(:respond_to?)
          .with(:fetch_with_lock)
          .and_return(false)
      end

      it "uses simple get/set pattern when advanced caching not available" do
        cache_key = "greeting:latest"

        expect(Langfuse::PromptCache).to receive(:build_key)
          .with("greeting", version: nil, label: nil)
          .and_return(cache_key)

        # First check cache (miss)
        expect(simple_cache).to receive(:get)
          .with(cache_key)
          .and_return(nil)

        # Fetch from API
        expect(api_client).to receive(:fetch_prompt_from_api)
          .with("greeting", version: nil, label: nil)
          .and_return(prompt_data)

        # Set in cache
        expect(simple_cache).to receive(:set)
          .with(cache_key, prompt_data)

        result = api_client.get_prompt("greeting")
        expect(result).to eq(prompt_data)
      end

      it "returns cached data when available" do
        cache_key = "greeting:latest"

        expect(Langfuse::PromptCache).to receive(:build_key)
          .with("greeting", version: nil, label: nil)
          .and_return(cache_key)

        # Cache hit
        expect(simple_cache).to receive(:get)
          .with(cache_key)
          .and_return(prompt_data)

        # Should not fetch from API or set cache
        expect(api_client).not_to receive(:fetch_prompt_from_api)
        expect(simple_cache).not_to receive(:set)

        result = api_client.get_prompt("greeting")
        expect(result).to eq(prompt_data)
      end
    end

    context "with no cache" do
      let(:api_client) do
        described_class.new(
          public_key: public_key,
          secret_key: secret_key,
          base_url: base_url,
          logger: logger,
          cache: nil
        )
      end

      it "fetches directly from API without caching" do
        expect(api_client).to receive(:fetch_prompt_from_api)
          .with("greeting", version: nil, label: nil)
          .and_return(prompt_data)

        result = api_client.get_prompt("greeting")
        expect(result).to eq(prompt_data)
      end
    end
  end

  describe "cache method detection" do
    context "SWR cache detection" do
      let(:swr_cache) { instance_double("Langfuse::RailsCacheAdapter") }
      let(:api_client) do
        described_class.new(
          public_key: public_key,
          secret_key: secret_key,
          base_url: base_url,
          cache: swr_cache
        )
      end

      it "correctly detects SWR capability" do
        allow(swr_cache).to receive(:respond_to?)
          .with(:fetch_with_stale_while_revalidate)
          .and_return(true)

        expect(swr_cache).to receive(:fetch_with_stale_while_revalidate)
        allow(swr_cache).to receive(:fetch_with_stale_while_revalidate)
          .and_return(prompt_data)

        api_client.get_prompt("test")
      end

      it "falls back when SWR not available but stampede protection is" do
        allow(swr_cache).to receive(:respond_to?)
          .with(:fetch_with_stale_while_revalidate)
          .and_return(false)
        allow(swr_cache).to receive(:respond_to?)
          .with(:fetch_with_lock)
          .and_return(true)

        expect(swr_cache).to receive(:fetch_with_lock)
        allow(swr_cache).to receive(:fetch_with_lock)
          .and_return(prompt_data)

        api_client.get_prompt("test")
      end
    end

    context "nil cache handling" do
      let(:api_client) do
        described_class.new(
          public_key: public_key,
          secret_key: secret_key,
          base_url: base_url,
          cache: nil
        )
      end

      it "handles nil cache gracefully" do
        expect(api_client).to receive(:fetch_prompt_from_api)
          .and_return(prompt_data)

        result = api_client.get_prompt("test")
        expect(result).to eq(prompt_data)
      end
    end
  end

  describe "error handling with SWR" do
    let(:swr_cache) { instance_double("Langfuse::RailsCacheAdapter") }
    let(:api_client) do
      described_class.new(
        public_key: public_key,
        secret_key: secret_key,
        base_url: base_url,
        logger: logger,
        cache: swr_cache
      )
    end

    before do
      allow(swr_cache).to receive(:respond_to?)
        .with(:fetch_with_stale_while_revalidate)
        .and_return(true)
    end

    it "propagates API errors when SWR cache fails" do
      allow(swr_cache).to receive(:fetch_with_stale_while_revalidate)
        .and_yield

      expect(api_client).to receive(:fetch_prompt_from_api)
        .and_raise(Langfuse::NotFoundError, "Prompt not found")

      expect do
        api_client.get_prompt("nonexistent")
      end.to raise_error(Langfuse::NotFoundError, "Prompt not found")
    end
  end
end
