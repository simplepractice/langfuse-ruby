# frozen_string_literal: true

RSpec.describe Langfuse do
  it "has a version number" do
    expect(Langfuse::VERSION).not_to be_nil
  end

  describe ".configuration" do
    it "returns a Config instance" do
      expect(described_class.configuration).to be_a(Langfuse::Config)
    end

    it "memoizes the configuration" do
      config1 = described_class.configuration
      config2 = described_class.configuration
      expect(config1).to eq(config2)
    end
  end

  describe ".configure" do
    it "yields configuration" do
      expect { |b| described_class.configure(&b) }.to yield_with_args(Langfuse::Config)
    end

    it "allows setting configuration values" do
      described_class.configure do |config|
        config.public_key = "test_pk"
        config.secret_key = "test_sk"
        config.cache_ttl = 300
      end

      expect(described_class.configuration.public_key).to eq("test_pk")
      expect(described_class.configuration.secret_key).to eq("test_sk")
      expect(described_class.configuration.cache_ttl).to eq(300)
    end
  end

  describe ".reset!" do
    it "resets configuration and client" do
      described_class.configure { |c| c.public_key = "test" }
      described_class.reset!

      expect(described_class.instance_variable_get(:@configuration)).to be_nil
      expect(described_class.instance_variable_get(:@client)).to be_nil
    end
  end

  # Client will be tested when implemented
  # describe ".client" do
  #   it "returns a Client instance" do
  #     described_class.configure do |config|
  #       config.public_key = "pk_test"
  #       config.secret_key = "sk_test"
  #     end
  #     expect(described_class.client).to be_a(Langfuse::Client)
  #   end
  # end
end
