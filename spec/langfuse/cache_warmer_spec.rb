# frozen_string_literal: true

require "spec_helper"

RSpec.describe Langfuse::CacheWarmer do
  let(:config) do
    Langfuse::Config.new do |c|
      c.public_key = "pk_test_123"
      c.secret_key = "sk_test_456"
      c.base_url = "https://cloud.langfuse.com"
      c.cache_ttl = 60
    end
  end

  let(:client) { Langfuse::Client.new(config) }
  let(:warmer) { described_class.new(client: client) }

  let(:text_prompt_response) do
    {
      "id" => "prompt-123",
      "name" => "greeting",
      "version" => 1,
      "type" => "text",
      "prompt" => "Hello {{name}}!",
      "labels" => ["production"],
      "tags" => ["greetings"],
      "config" => {}
    }
  end

  let(:chat_prompt_response) do
    {
      "id" => "prompt-456",
      "name" => "conversation",
      "version" => 2,
      "type" => "chat",
      "prompt" => [
        { "role" => "system", "content" => "You are helpful" }
      ],
      "labels" => [],
      "tags" => [],
      "config" => {}
    }
  end

  describe "#initialize" do
    it "uses global client by default" do
      Langfuse.configure do |c|
        c.public_key = "pk_global"
        c.secret_key = "sk_global"
      end

      default_warmer = described_class.new
      expect(default_warmer.client).to eq(Langfuse.client)
    end

    it "accepts custom client" do
      custom_warmer = described_class.new(client: client)
      expect(custom_warmer.client).to eq(client)
    end
  end

  describe "#warm" do
    context "when all prompts are found" do
      before do
        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .to_return(status: 200, body: text_prompt_response.to_json, headers: { "Content-Type" => "application/json" })

        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/conversation")
          .to_return(status: 200, body: chat_prompt_response.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "returns success results" do
        results = warmer.warm(%w[greeting conversation])

        expect(results[:success]).to eq(%w[greeting conversation])
        expect(results[:failed]).to be_empty
      end

      it "caches the prompts" do
        warmer.warm(["greeting"])

        # Subsequent call should use cache (no new HTTP request)
        cached_prompt = client.get_prompt("greeting")
        expect(cached_prompt.name).to eq("greeting")

        # Verify only one HTTP request was made
        expect(a_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting"))
          .to have_been_made.once
      end
    end

    context "when some prompts are not found" do
      before do
        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .to_return(status: 200, body: text_prompt_response.to_json, headers: { "Content-Type" => "application/json" })

        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/missing")
          .to_return(status: 404, body: { message: "Not found" }.to_json)
      end

      it "returns mixed results" do
        results = warmer.warm(%w[greeting missing])

        expect(results[:success]).to eq(["greeting"])
        expect(results[:failed]).to eq([{ name: "missing", error: "Not found" }])
      end
    end

    context "when authentication fails" do
      before do
        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .to_return(status: 401, body: { message: "Unauthorized" }.to_json)
      end

      it "returns failed result with unauthorized error" do
        results = warmer.warm(["greeting"])

        expect(results[:success]).to be_empty
        expect(results[:failed]).to eq([{ name: "greeting", error: "Unauthorized" }])
      end
    end

    context "when API error occurs" do
      before do
        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .to_return(
            status: 500,
            body: { message: "Internal error" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns failed result with error message" do
        results = warmer.warm(["greeting"])

        expect(results[:success]).to be_empty
        expect(results[:failed].first[:name]).to eq("greeting")
        expect(results[:failed].first[:error]).to include("API request failed")
      end
    end

    context "with specific versions" do
      before do
        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .with(query: { version: "2" })
          .to_return(
            status: 200,
            body: text_prompt_response.merge("version" => 2).to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "fetches prompts with specified versions" do
        results = warmer.warm(["greeting"], versions: { "greeting" => 2 })

        expect(results[:success]).to eq(["greeting"])
        expect(a_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .with(query: { version: "2" })).to have_been_made.once
      end
    end

    context "with labels" do
      before do
        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .with(query: { label: "production" })
          .to_return(status: 200, body: text_prompt_response.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "fetches prompts with specified labels" do
        results = warmer.warm(["greeting"], labels: { "greeting" => "production" })

        expect(results[:success]).to eq(["greeting"])
        expect(a_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .with(query: { label: "production" })).to have_been_made.once
      end
    end
  end

  describe "#warm!" do
    context "when all prompts are found" do
      before do
        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .to_return(status: 200, body: text_prompt_response.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "returns success results" do
        results = warmer.warm!(["greeting"])

        expect(results[:success]).to eq(["greeting"])
        expect(results[:failed]).to be_empty
      end
    end

    context "when any prompt fails" do
      before do
        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .to_return(status: 200, body: text_prompt_response.to_json, headers: { "Content-Type" => "application/json" })

        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/missing")
          .to_return(status: 404, body: { message: "Not found" }.to_json)
      end

      it "raises CacheWarmingError" do
        expect do
          warmer.warm!(%w[greeting missing])
        end.to raise_error(Langfuse::CacheWarmingError, /Failed to cache prompts: missing/)
      end
    end
  end

  describe "#cache_enabled?" do
    context "when cache is enabled" do
      it "returns true" do
        expect(warmer.cache_enabled?).to be true
      end
    end

    # rubocop:disable RSpec/MultipleMemoizedHelpers
    context "when cache is disabled" do
      let(:no_cache_config) do
        Langfuse::Config.new do |c|
          c.public_key = "pk_test_123"
          c.secret_key = "sk_test_456"
          c.cache_ttl = 0
        end
      end

      let(:no_cache_client) { Langfuse::Client.new(no_cache_config) }
      let(:no_cache_warmer) { described_class.new(client: no_cache_client) }

      it "returns false" do
        expect(no_cache_warmer.cache_enabled?).to be false
      end
    end
    # rubocop:enable RSpec/MultipleMemoizedHelpers
  end

  describe "#warm_all" do
    let(:prompts_list_response) do
      {
        "data" => [
          { "name" => "greeting", "version" => 1, "type" => "text" },
          { "name" => "conversation", "version" => 2, "type" => "chat" },
          { "name" => "greeting", "version" => 2, "type" => "text" } # Duplicate name
        ],
        "meta" => { "totalItems" => 3 }
      }
    end

    context "when prompts are found" do
      before do
        # Stub the list_prompts API call
        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts")
          .to_return(
            status: 200,
            body: prompts_list_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        # Stub individual prompt fetches WITH "production" label (default)
        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .with(query: { label: "production" })
          .to_return(status: 200, body: text_prompt_response.to_json, headers: { "Content-Type" => "application/json" })

        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/conversation")
          .with(query: { label: "production" })
          .to_return(status: 200, body: chat_prompt_response.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "auto-discovers and warms all unique prompts with production label by default" do
        results = warmer.warm_all

        expect(results[:success]).to match_array(%w[greeting conversation])
        expect(results[:failed]).to be_empty

        # Verify production label was used
        expect(a_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .with(query: { label: "production" })).to have_been_made.once
        expect(a_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/conversation")
          .with(query: { label: "production" })).to have_been_made.once
      end

      it "removes duplicate prompt names" do
        warmer.warm_all

        # Should only fetch each unique prompt name once
        expect(a_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .with(query: { label: "production" })).to have_been_made.once
        expect(a_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/conversation")
          .with(query: { label: "production" })).to have_been_made.once
      end

      it "supports warming without any label when explicitly set to nil" do
        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .to_return(status: 200, body: text_prompt_response.to_json, headers: { "Content-Type" => "application/json" })

        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/conversation")
          .to_return(status: 200, body: chat_prompt_response.to_json, headers: { "Content-Type" => "application/json" })

        results = warmer.warm_all(default_label: nil)

        expect(results[:success]).to match_array(%w[greeting conversation])

        # Verify NO label was used (fetches latest)
        expect(a_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .with(query: {})).to have_been_made.once
        expect(a_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/conversation")
          .with(query: {})).to have_been_made.once
      end
    end

    context "when some prompts fail to warm" do
      before do
        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts")
          .to_return(
            status: 200,
            body: prompts_list_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .with(query: { label: "production" })
          .to_return(status: 200, body: text_prompt_response.to_json, headers: { "Content-Type" => "application/json" })

        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/conversation")
          .with(query: { label: "production" })
          .to_return(status: 404, body: { message: "Not found" }.to_json)
      end

      it "returns mixed results" do
        results = warmer.warm_all

        expect(results[:success]).to eq(["greeting"])
        expect(results[:failed]).to eq([{ name: "conversation", error: "Not found" }])
      end
    end

    context "with specific versions" do
      before do
        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts")
          .to_return(
            status: 200,
            body: prompts_list_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        # Version takes precedence - when version is specified, label is NOT sent
        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .with(query: { version: "2" })
          .to_return(
            status: 200,
            body: text_prompt_response.merge("version" => 2).to_json,
            headers: { "Content-Type" => "application/json" }
          )

        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/conversation")
          .with(query: { label: "production" })
          .to_return(status: 200, body: chat_prompt_response.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "supports version overrides for specific prompts (version takes precedence over label)" do
        results = warmer.warm_all(versions: { "greeting" => 2 })

        expect(results[:success]).to match_array(%w[greeting conversation])
        # greeting uses version (no label), conversation uses default label
        expect(a_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .with(query: { version: "2" })).to have_been_made.once
        expect(a_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/conversation")
          .with(query: { label: "production" })).to have_been_made.once
      end
    end

    context "with custom default label" do
      before do
        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts")
          .to_return(
            status: 200,
            body: prompts_list_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .with(query: { label: "staging" })
          .to_return(status: 200, body: text_prompt_response.to_json, headers: { "Content-Type" => "application/json" })

        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/conversation")
          .with(query: { label: "staging" })
          .to_return(status: 200, body: chat_prompt_response.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "supports using a different default label" do
        results = warmer.warm_all(default_label: "staging")

        expect(results[:success]).to match_array(%w[greeting conversation])
        expect(a_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .with(query: { label: "staging" })).to have_been_made.once
        expect(a_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/conversation")
          .with(query: { label: "staging" })).to have_been_made.once
      end
    end

    context "with label overrides" do
      before do
        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts")
          .to_return(
            status: 200,
            body: prompts_list_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .with(query: { label: "staging" })
          .to_return(status: 200, body: text_prompt_response.to_json, headers: { "Content-Type" => "application/json" })

        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/conversation")
          .with(query: { label: "production" })
          .to_return(status: 200, body: chat_prompt_response.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "supports label overrides for specific prompts" do
        results = warmer.warm_all(labels: { "greeting" => "staging" })

        expect(results[:success]).to match_array(%w[greeting conversation])
        # greeting uses override (staging), conversation uses default (production)
        expect(a_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
          .with(query: { label: "staging" })).to have_been_made.once
        expect(a_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/conversation")
          .with(query: { label: "production" })).to have_been_made.once
      end
    end

    context "when no prompts exist" do
      before do
        stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts")
          .to_return(status: 200, body: { "data" => [],
                                          "meta" => {} }.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "returns empty results" do
        results = warmer.warm_all

        expect(results[:success]).to be_empty
        expect(results[:failed]).to be_empty
      end
    end
  end

  describe "#cache_stats" do
    context "with in-memory cache" do
      it "returns cache statistics" do
        stats = warmer.cache_stats

        expect(stats).to be_a(Hash)
        expect(stats[:backend]).to eq("PromptCache")
        expect(stats[:ttl]).to eq(60)
        expect(stats[:size]).to eq(0)
        expect(stats[:max_size]).to eq(1000)
      end
    end

    context "with Rails.cache backend" do
      let(:rails_config) do
        Langfuse::Config.new do |c|
          c.public_key = "pk_test_123"
          c.secret_key = "sk_test_456"
          c.cache_ttl = 120
          c.cache_backend = :rails
        end
      end

      let(:mock_rails_cache) { double("Rails.cache") }

      before do
        rails_class = Class.new do
          def self.cache
            @cache ||= nil
          end

          class << self
            attr_writer :cache
          end
        end

        stub_const("Rails", rails_class)
        Rails.cache = mock_rails_cache
      end

      it "returns Rails cache statistics" do
        rails_client = Langfuse::Client.new(rails_config)
        rails_warmer = described_class.new(client: rails_client)

        stats = rails_warmer.cache_stats

        expect(stats).to be_a(Hash)
        expect(stats[:backend]).to eq("RailsCacheAdapter")
        expect(stats[:ttl]).to eq(120)
        expect(stats[:size]).to be_nil # Rails.cache doesn't support size
      end
    end

    # rubocop:disable RSpec/MultipleMemoizedHelpers
    context "when cache is disabled" do
      let(:no_cache_config) do
        Langfuse::Config.new do |c|
          c.public_key = "pk_test_123"
          c.secret_key = "sk_test_456"
          c.cache_ttl = 0
        end
      end

      let(:no_cache_client) { Langfuse::Client.new(no_cache_config) }
      let(:no_cache_warmer) { described_class.new(client: no_cache_client) }

      it "returns nil" do
        expect(no_cache_warmer.cache_stats).to be_nil
      end
    end
    # rubocop:enable RSpec/MultipleMemoizedHelpers
  end
end
