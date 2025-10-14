# frozen_string_literal: true

RSpec.describe Langfuse::ApiClient do
  let(:public_key) { "pk_test_123" }
  let(:secret_key) { "sk_test_456" }
  let(:base_url) { "https://cloud.langfuse.com" }
  let(:api_client) do
    described_class.new(
      public_key: public_key,
      secret_key: secret_key,
      base_url: base_url,
      timeout: 10
    )
  end

  describe "#initialize" do
    it "sets public_key" do
      expect(api_client.public_key).to eq(public_key)
    end

    it "sets secret_key" do
      expect(api_client.secret_key).to eq(secret_key)
    end

    it "sets base_url" do
      expect(api_client.base_url).to eq(base_url)
    end

    it "sets timeout" do
      expect(api_client.timeout).to eq(10)
    end

    it "creates a default logger when none provided" do
      expect(api_client.logger).to be_a(Logger)
    end

    it "accepts a custom logger" do
      custom_logger = Logger.new($stdout)
      client = described_class.new(
        public_key: public_key,
        secret_key: secret_key,
        base_url: base_url,
        logger: custom_logger
      )
      expect(client.logger).to eq(custom_logger)
    end
  end

  describe "#connection" do
    it "returns a Faraday connection" do
      expect(api_client.connection).to be_a(Faraday::Connection)
    end

    it "memoizes the connection" do
      conn1 = api_client.connection
      conn2 = api_client.connection
      expect(conn1).to eq(conn2)
    end

    it "creates a new connection with custom timeout" do
      default_conn = api_client.connection
      custom_conn = api_client.connection(timeout: 20)

      expect(custom_conn).to be_a(Faraday::Connection)
      expect(custom_conn).not_to eq(default_conn)
    end

    it "configures the connection with correct base URL" do
      conn = api_client.connection
      expect(conn.url_prefix.to_s).to eq("#{base_url}/")
    end

    it "includes Authorization header" do
      conn = api_client.connection
      expect(conn.headers["Authorization"]).to start_with("Basic ")
    end

    it "includes User-Agent header" do
      conn = api_client.connection
      expect(conn.headers["User-Agent"]).to eq("langfuse-ruby/#{Langfuse::VERSION}")
    end

    it "includes Content-Type header" do
      conn = api_client.connection
      expect(conn.headers["Content-Type"]).to eq("application/json")
    end
  end

  describe "#authorization_header" do
    it "generates correct Basic Auth header" do
      # Basic Auth format: "Basic " + base64(public_key:secret_key)
      expected_credentials = "#{public_key}:#{secret_key}"
      expected_encoded = Base64.strict_encode64(expected_credentials)
      expected_header = "Basic #{expected_encoded}"

      auth_header = api_client.send(:authorization_header)
      expect(auth_header).to eq(expected_header)
    end

    it "uses strict encoding (no newlines)" do
      auth_header = api_client.send(:authorization_header)
      expect(auth_header).not_to include("\n")
    end

    it "works with special characters in credentials" do
      client = described_class.new(
        public_key: "pk_test!@#$%",
        secret_key: "sk_test^&*()",
        base_url: base_url
      )

      auth_header = client.send(:authorization_header)
      expect(auth_header).to start_with("Basic ")

      # Decode and verify
      encoded = auth_header.sub("Basic ", "")
      decoded = Base64.strict_decode64(encoded)
      expect(decoded).to eq("pk_test!@#$%:sk_test^&*()")
    end
  end

  describe "#user_agent" do
    it "includes gem name and version" do
      user_agent = api_client.send(:user_agent)
      expect(user_agent).to eq("langfuse-ruby/#{Langfuse::VERSION}")
    end
  end

  describe "timeout configuration" do
    it "uses default timeout when none specified" do
      client = described_class.new(
        public_key: public_key,
        secret_key: secret_key,
        base_url: base_url
      )
      conn = client.connection
      expect(conn.options.timeout).to eq(5)
    end

    it "uses custom timeout when specified" do
      conn = api_client.connection
      expect(conn.options.timeout).to eq(10)
    end

    it "overrides timeout for specific connection" do
      conn = api_client.connection(timeout: 30)
      expect(conn.options.timeout).to eq(30)
    end
  end

  describe "connection middleware" do
    let(:conn) { api_client.connection }

    it "includes JSON request middleware" do
      handlers = conn.builder.handlers.map(&:name)
      expect(handlers).to include("Faraday::Request::Json")
    end

    it "includes JSON response middleware" do
      handlers = conn.builder.handlers.map(&:name)
      expect(handlers).to include("Faraday::Response::Json")
    end

    it "uses Faraday default adapter" do
      # Adapter is configured but may not show in handlers list in Faraday 2.x
      # We'll verify it works when making actual requests in Phase 1.3
      expect(conn.adapter).to eq(Faraday::Adapter::NetHttp)
    end
  end
end
