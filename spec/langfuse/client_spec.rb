# frozen_string_literal: true

RSpec.describe Langfuse::Client do
  let(:valid_config) do
    Langfuse::Config.new do |config|
      config.public_key = "pk_test_123"
      config.secret_key = "sk_test_456"
      config.base_url = "https://cloud.langfuse.com"
    end
  end

  describe "#initialize" do
    it "creates a client with valid config" do
      client = described_class.new(valid_config)
      expect(client).to be_a(described_class)
    end

    it "sets the config" do
      client = described_class.new(valid_config)
      expect(client.config).to eq(valid_config)
    end

    it "creates an api_client" do
      client = described_class.new(valid_config)
      expect(client.api_client).to be_a(Langfuse::ApiClient)
    end

    it "validates configuration on initialization" do
      invalid_config = Langfuse::Config.new
      expect do
        described_class.new(invalid_config)
      end.to raise_error(Langfuse::ConfigurationError)
    end

    context "with caching enabled" do
      let(:config_with_cache) do
        Langfuse::Config.new do |config|
          config.public_key = "pk_test_123"
          config.secret_key = "sk_test_456"
          config.base_url = "https://cloud.langfuse.com"
          config.cache_ttl = 60
          config.cache_max_size = 100
        end
      end

      it "creates api_client with cache" do
        client = described_class.new(config_with_cache)
        expect(client.api_client.cache).to be_a(Langfuse::PromptCache)
      end

      it "configures cache with correct TTL" do
        client = described_class.new(config_with_cache)
        expect(client.api_client.cache.ttl).to eq(60)
      end

      it "configures cache with correct max_size" do
        client = described_class.new(config_with_cache)
        expect(client.api_client.cache.max_size).to eq(100)
      end
    end

    context "with caching disabled" do
      let(:config_without_cache) do
        Langfuse::Config.new do |config|
          config.public_key = "pk_test_123"
          config.secret_key = "sk_test_456"
          config.base_url = "https://cloud.langfuse.com"
          config.cache_ttl = 0
        end
      end

      it "creates api_client without cache" do
        client = described_class.new(config_without_cache)
        expect(client.api_client.cache).to be_nil
      end
    end
  end

  describe "#get_prompt" do
    let(:client) { described_class.new(valid_config) }
    let(:base_url) { valid_config.base_url }

    context "with text prompt" do
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

      before do
        stub_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
          .to_return(
            status: 200,
            body: text_prompt_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns a TextPromptClient" do
        result = client.get_prompt("greeting")
        expect(result).to be_a(Langfuse::TextPromptClient)
      end

      it "returns client with correct prompt data" do
        result = client.get_prompt("greeting")
        expect(result.name).to eq("greeting")
        expect(result.version).to eq(1)
        expect(result.prompt).to eq("Hello {{name}}!")
      end
    end

    context "with chat prompt" do
      let(:chat_prompt_response) do
        {
          "id" => "prompt-456",
          "name" => "chat-assistant",
          "version" => 2,
          "type" => "chat",
          "prompt" => [
            { "role" => "system", "content" => "You are {{role}}" },
            { "role" => "user", "content" => "Hello!" }
          ],
          "labels" => ["production"],
          "tags" => ["chat"],
          "config" => {}
        }
      end

      before do
        stub_request(:get, "#{base_url}/api/public/v2/prompts/chat-assistant")
          .to_return(
            status: 200,
            body: chat_prompt_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns a ChatPromptClient" do
        result = client.get_prompt("chat-assistant")
        expect(result).to be_a(Langfuse::ChatPromptClient)
      end

      it "returns client with correct prompt data" do
        result = client.get_prompt("chat-assistant")
        expect(result.name).to eq("chat-assistant")
        expect(result.version).to eq(2)
        expect(result.prompt).to be_an(Array)
      end
    end

    context "with unknown prompt type" do
      let(:unknown_type_response) do
        {
          "id" => "prompt-789",
          "name" => "unknown",
          "version" => 1,
          "type" => "unknown",
          "prompt" => "Some prompt",
          "labels" => [],
          "tags" => [],
          "config" => {}
        }
      end

      before do
        stub_request(:get, "#{base_url}/api/public/v2/prompts/unknown")
          .to_return(
            status: 200,
            body: unknown_type_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises ApiError" do
        expect do
          client.get_prompt("unknown")
        end.to raise_error(Langfuse::ApiError, "Unknown prompt type: unknown")
      end
    end

    context "with version parameter" do
      let(:text_prompt_response) do
        {
          "id" => "prompt-123",
          "name" => "greeting",
          "version" => 2,
          "type" => "text",
          "prompt" => "Hello {{name}}!",
          "labels" => [],
          "tags" => [],
          "config" => {}
        }
      end

      before do
        stub_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
          .with(query: { version: "2" })
          .to_return(
            status: 200,
            body: text_prompt_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "passes version to api_client" do
        result = client.get_prompt("greeting", version: 2)
        expect(result.version).to eq(2)
      end

      it "makes request with version parameter" do
        client.get_prompt("greeting", version: 2)
        expect(
          a_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
            .with(query: { version: "2" })
        ).to have_been_made.once
      end
    end

    context "with label parameter" do
      let(:text_prompt_response) do
        {
          "id" => "prompt-123",
          "name" => "greeting",
          "version" => 1,
          "type" => "text",
          "prompt" => "Hello {{name}}!",
          "labels" => ["production"],
          "tags" => [],
          "config" => {}
        }
      end

      before do
        stub_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
          .with(query: { label: "production" })
          .to_return(
            status: 200,
            body: text_prompt_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "passes label to api_client" do
        result = client.get_prompt("greeting", label: "production")
        expect(result.labels).to include("production")
      end

      it "makes request with label parameter" do
        client.get_prompt("greeting", label: "production")
        expect(
          a_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
            .with(query: { label: "production" })
        ).to have_been_made.once
      end
    end

    context "when prompt is not found" do
      before do
        stub_request(:get, "#{base_url}/api/public/v2/prompts/missing")
          .to_return(status: 404, body: { message: "Not found" }.to_json)
      end

      it "raises NotFoundError" do
        expect do
          client.get_prompt("missing")
        end.to raise_error(Langfuse::NotFoundError)
      end
    end

    context "when authentication fails" do
      before do
        stub_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
          .to_return(status: 401, body: { message: "Unauthorized" }.to_json)
      end

      it "raises UnauthorizedError" do
        expect do
          client.get_prompt("greeting")
        end.to raise_error(Langfuse::UnauthorizedError)
      end
    end

    context "when API returns an error" do
      before do
        stub_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
          .to_return(
            status: 500,
            body: { message: "Internal server error" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises ApiError" do
        expect do
          client.get_prompt("greeting")
        end.to raise_error(Langfuse::ApiError, /API request failed/)
      end
    end

    context "with caching enabled" do
      let(:config_with_cache) do
        Langfuse::Config.new do |config|
          config.public_key = "pk_test_123"
          config.secret_key = "sk_test_456"
          config.base_url = "https://cloud.langfuse.com"
          config.cache_ttl = 60
        end
      end

      let(:cached_client) { described_class.new(config_with_cache) }

      let(:text_prompt_response) do
        {
          "id" => "prompt-123",
          "name" => "greeting",
          "version" => 1,
          "type" => "text",
          "prompt" => "Hello {{name}}!",
          "labels" => [],
          "tags" => [],
          "config" => {}
        }
      end

      before do
        stub_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
          .to_return(
            status: 200,
            body: text_prompt_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "caches prompt responses" do
        # First call - hits API
        first_result = cached_client.get_prompt("greeting")

        # Second call - should use cache
        second_result = cached_client.get_prompt("greeting")

        # Verify same data returned
        expect(second_result.name).to eq(first_result.name)
        expect(second_result.version).to eq(first_result.version)

        # Verify API was only called once
        expect(
          a_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
        ).to have_been_made.once
      end
    end

    context "with fallback support" do
      context "when prompt not found (404)" do
        before do
          stub_request(:get, "#{base_url}/api/public/v2/prompts/missing")
            .to_return(status: 404, body: { message: "Not found" }.to_json)
        end

        it "returns fallback text prompt when provided" do
          result = client.get_prompt("missing", fallback: "Hello {{name}}!", type: :text)
          expect(result).to be_a(Langfuse::TextPromptClient)
          expect(result.prompt).to eq("Hello {{name}}!")
        end

        it "sets fallback prompt metadata correctly" do
          result = client.get_prompt("missing", fallback: "Hello!", type: :text)
          expect(result.name).to eq("missing")
          expect(result.version).to eq(0)
          expect(result.tags).to include("fallback")
        end

        it "raises error when no fallback provided" do
          expect do
            client.get_prompt("missing")
          end.to raise_error(Langfuse::NotFoundError)
        end
      end

      context "when authentication fails (401)" do
        before do
          stub_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
            .to_return(status: 401, body: { message: "Unauthorized" }.to_json)
        end

        it "returns fallback text prompt when provided" do
          result = client.get_prompt("greeting", fallback: "Hello {{name}}!", type: :text)
          expect(result).to be_a(Langfuse::TextPromptClient)
          expect(result.prompt).to eq("Hello {{name}}!")
        end

        it "raises error when no fallback provided" do
          expect do
            client.get_prompt("greeting")
          end.to raise_error(Langfuse::UnauthorizedError)
        end
      end

      context "when API error occurs (500)" do
        before do
          stub_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
            .to_return(
              status: 500,
              body: { message: "Internal server error" }.to_json,
              headers: { "Content-Type" => "application/json" }
            )
        end

        it "returns fallback text prompt when provided" do
          result = client.get_prompt("greeting", fallback: "Hello {{name}}!", type: :text)
          expect(result).to be_a(Langfuse::TextPromptClient)
          expect(result.prompt).to eq("Hello {{name}}!")
        end

        it "raises error when no fallback provided" do
          expect do
            client.get_prompt("greeting")
          end.to raise_error(Langfuse::ApiError)
        end
      end

      context "with chat prompt fallback" do
        let(:fallback_messages) do
          [
            { "role" => "system", "content" => "You are a {{role}} assistant" }
          ]
        end

        before do
          stub_request(:get, "#{base_url}/api/public/v2/prompts/chat-bot")
            .to_return(status: 404, body: { message: "Not found" }.to_json)
        end

        it "returns fallback chat prompt when provided" do
          result = client.get_prompt("chat-bot", fallback: fallback_messages, type: :chat)
          expect(result).to be_a(Langfuse::ChatPromptClient)
          expect(result.prompt).to eq(fallback_messages)
        end

        it "sets fallback chat prompt metadata correctly" do
          result = client.get_prompt("chat-bot", fallback: fallback_messages, type: :chat)
          expect(result.name).to eq("chat-bot")
          expect(result.version).to eq(0)
          expect(result.tags).to include("fallback")
        end
      end

      context "with fallback validation" do
        it "requires type parameter when fallback is provided" do
          expect do
            client.get_prompt("greeting", fallback: "Hello!")
          end.to raise_error(ArgumentError, /type parameter is required/)
        end

        it "accepts :text type" do
          stub_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
            .to_return(status: 404, body: { message: "Not found" }.to_json)

          result = client.get_prompt("greeting", fallback: "Hello!", type: :text)
          expect(result).to be_a(Langfuse::TextPromptClient)
        end

        it "accepts :chat type" do
          stub_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
            .to_return(status: 404, body: { message: "Not found" }.to_json)

          result = client.get_prompt("greeting", fallback: [], type: :chat)
          expect(result).to be_a(Langfuse::ChatPromptClient)
        end

        it "rejects invalid type" do
          stub_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
            .to_return(status: 404, body: { message: "Not found" }.to_json)

          expect do
            client.get_prompt("greeting", fallback: "Hello!", type: :invalid)
          end.to raise_error(ArgumentError, /Invalid type.*Must be :text or :chat/)
        end
      end

      context "with logging" do
        it "logs warning when using fallback" do
          stub_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
            .to_return(status: 404, body: { message: "Not found" }.to_json)

          expect(client.config.logger).to receive(:warn)
            .with(/Langfuse API error for prompt 'greeting'.*Using fallback/)

          client.get_prompt("greeting", fallback: "Hello!", type: :text)
        end
      end
    end
  end

  describe "#compile_prompt" do
    let(:client) { described_class.new(valid_config) }
    let(:base_url) { valid_config.base_url }

    context "with text prompt" do
      let(:text_prompt_response) do
        {
          "id" => "prompt-123",
          "name" => "greeting",
          "version" => 1,
          "type" => "text",
          "prompt" => "Hello {{name}}!",
          "labels" => [],
          "tags" => [],
          "config" => {}
        }
      end

      before do
        stub_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
          .to_return(
            status: 200,
            body: text_prompt_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "fetches and compiles prompt in one call" do
        result = client.compile_prompt("greeting", variables: { name: "Alice" })
        expect(result).to eq("Hello Alice!")
      end

      it "returns compiled string for text prompts" do
        result = client.compile_prompt("greeting", variables: { name: "Bob" })
        expect(result).to be_a(String)
        expect(result).to eq("Hello Bob!")
      end

      it "works without variables" do
        result = client.compile_prompt("greeting", variables: {})
        expect(result).to eq("Hello {{name}}!")
      end
    end

    context "with chat prompt" do
      let(:chat_prompt_response) do
        {
          "id" => "prompt-456",
          "name" => "support-bot",
          "version" => 1,
          "type" => "chat",
          "prompt" => [
            { "role" => "system", "content" => "You are a {{role}} agent" }
          ],
          "labels" => [],
          "tags" => [],
          "config" => {}
        }
      end

      before do
        stub_request(:get, "#{base_url}/api/public/v2/prompts/support-bot")
          .to_return(
            status: 200,
            body: chat_prompt_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "fetches and compiles chat prompt" do
        result = client.compile_prompt("support-bot", variables: { role: "support" })
        expect(result).to be_an(Array)
        expect(result.first[:content]).to eq("You are a support agent")
      end

      it "returns array of messages for chat prompts" do
        result = client.compile_prompt("support-bot", variables: { role: "billing" })
        expect(result).to be_an(Array)
        expect(result).to all(be_a(Hash))
        expect(result.first).to have_key(:role)
        expect(result.first).to have_key(:content)
      end
    end

    context "with version parameter" do
      let(:text_prompt_response) do
        {
          "id" => "prompt-123",
          "name" => "greeting",
          "version" => 2,
          "type" => "text",
          "prompt" => "Hi {{name}}!",
          "labels" => [],
          "tags" => [],
          "config" => {}
        }
      end

      before do
        stub_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
          .with(query: { version: "2" })
          .to_return(
            status: 200,
            body: text_prompt_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "fetches specific version and compiles" do
        result = client.compile_prompt("greeting", variables: { name: "Charlie" }, version: 2)
        expect(result).to eq("Hi Charlie!")
      end
    end

    context "with label parameter" do
      let(:text_prompt_response) do
        {
          "id" => "prompt-123",
          "name" => "greeting",
          "version" => 1,
          "type" => "text",
          "prompt" => "Greetings {{name}}!",
          "labels" => ["production"],
          "tags" => [],
          "config" => {}
        }
      end

      before do
        stub_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
          .with(query: { label: "production" })
          .to_return(
            status: 200,
            body: text_prompt_response.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "fetches labeled version and compiles" do
        result = client.compile_prompt("greeting", variables: { name: "Dave" }, label: "production")
        expect(result).to eq("Greetings Dave!")
      end
    end

    context "when prompt is not found" do
      before do
        stub_request(:get, "#{base_url}/api/public/v2/prompts/missing")
          .to_return(status: 404, body: { message: "Not found" }.to_json)
      end

      it "raises NotFoundError" do
        expect do
          client.compile_prompt("missing", variables: { name: "Test" })
        end.to raise_error(Langfuse::NotFoundError)
      end
    end

    context "with fallback support" do
      before do
        stub_request(:get, "#{base_url}/api/public/v2/prompts/missing")
          .to_return(status: 404, body: { message: "Not found" }.to_json)
      end

      it "compiles fallback text prompt when API fails" do
        result = client.compile_prompt(
          "missing",
          variables: { name: "Alice" },
          fallback: "Hello {{name}}!",
          type: :text
        )
        expect(result).to eq("Hello Alice!")
      end

      it "compiles fallback chat prompt when API fails" do
        fallback_messages = [
          { "role" => "system", "content" => "You are a {{role}} assistant" }
        ]
        result = client.compile_prompt(
          "missing",
          variables: { role: "helpful" },
          fallback: fallback_messages,
          type: :chat
        )
        expect(result).to be_an(Array)
        expect(result.first[:content]).to eq("You are a helpful assistant")
      end

      it "works with version and label parameters" do
        stub_request(:get, "#{base_url}/api/public/v2/prompts/greeting")
          .with(query: { version: "2" })
          .to_return(status: 404, body: { message: "Not found" }.to_json)

        result = client.compile_prompt(
          "greeting",
          variables: { name: "Bob" },
          version: 2,
          fallback: "Hi {{name}}!",
          type: :text
        )
        expect(result).to eq("Hi Bob!")
      end

      it "requires type parameter with fallback" do
        expect do
          client.compile_prompt(
            "missing",
            variables: { name: "Test" },
            fallback: "Hello!"
          )
        end.to raise_error(ArgumentError, /type parameter is required/)
      end
    end
  end
end
