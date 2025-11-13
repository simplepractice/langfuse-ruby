# frozen_string_literal: true

require "spec_helper"

RSpec.describe Langfuse::Config do
  describe "SWR configuration options" do
    let(:config) { described_class.new }

    describe "default values" do
      it "sets cache_stale_while_revalidate to false by default" do
        expect(config.cache_stale_while_revalidate).to be false
      end

      it "sets cache_stale_ttl to 300 seconds by default" do
        expect(config.cache_stale_ttl).to eq(300)
      end

      it "sets cache_refresh_threads to 5 by default" do
        expect(config.cache_refresh_threads).to eq(5)
      end
    end

    describe "configuration block" do
      it "allows setting SWR options" do
        config = described_class.new do |c|
          c.cache_stale_while_revalidate = true
          c.cache_stale_ttl = 600
          c.cache_refresh_threads = 10
        end

        expect(config.cache_stale_while_revalidate).to be true
        expect(config.cache_stale_ttl).to eq(600)
        expect(config.cache_refresh_threads).to eq(10)
      end
    end

    describe "validation" do
      before do
        config.public_key = "pk_test"
        config.secret_key = "sk_test"
      end

      context "cache_stale_ttl validation" do
        it "accepts positive values" do
          config.cache_stale_ttl = 300
          expect { config.validate! }.not_to raise_error
        end

        it "accepts zero" do
          config.cache_stale_ttl = 0
          expect { config.validate! }.not_to raise_error
        end

        it "rejects negative values" do
          config.cache_stale_ttl = -1
          expect { config.validate! }.to raise_error(
            Langfuse::ConfigurationError,
            "cache_stale_ttl must be non-negative"
          )
        end

        it "rejects nil values" do
          config.cache_stale_ttl = nil
          expect { config.validate! }.to raise_error(
            Langfuse::ConfigurationError,
            "cache_stale_ttl must be non-negative"
          )
        end
      end

      context "cache_refresh_threads validation" do
        it "accepts positive values" do
          config.cache_refresh_threads = 5
          expect { config.validate! }.not_to raise_error
        end

        it "rejects zero" do
          config.cache_refresh_threads = 0
          expect { config.validate! }.to raise_error(
            Langfuse::ConfigurationError,
            "cache_refresh_threads must be positive"
          )
        end

        it "rejects negative values" do
          config.cache_refresh_threads = -1
          expect { config.validate! }.to raise_error(
            Langfuse::ConfigurationError,
            "cache_refresh_threads must be positive"
          )
        end

        it "rejects nil values" do
          config.cache_refresh_threads = nil
          expect { config.validate! }.to raise_error(
            Langfuse::ConfigurationError,
            "cache_refresh_threads must be positive"
          )
        end
      end

      context "SWR with cache backend validation" do
        it "allows SWR with Rails cache backend" do
          config.cache_backend = :rails
          config.cache_stale_while_revalidate = true
          expect { config.validate! }.not_to raise_error
        end

        it "allows SWR disabled with any cache backend" do
          config.cache_backend = :memory
          config.cache_stale_while_revalidate = false
          expect { config.validate! }.not_to raise_error
        end

        it "rejects SWR with memory cache backend" do
          config.cache_backend = :memory
          config.cache_stale_while_revalidate = true
          expect { config.validate! }.to raise_error(
            Langfuse::ConfigurationError,
            "cache_stale_while_revalidate requires cache_backend to be :rails"
          )
        end
      end
    end

    describe "constants" do
      it "defines correct default values" do
        expect(Langfuse::Config::DEFAULT_CACHE_STALE_WHILE_REVALIDATE).to be false
        expect(Langfuse::Config::DEFAULT_CACHE_STALE_TTL).to eq(300)
        expect(Langfuse::Config::DEFAULT_CACHE_REFRESH_THREADS).to eq(5)
      end
    end
  end

  describe "SWR integration with existing config" do
    it "works with all configuration options together" do
      config = described_class.new do |c|
        c.public_key = "pk_test"
        c.secret_key = "sk_test"
        c.base_url = "https://test.langfuse.com"
        c.timeout = 10
        c.cache_ttl = 120
        c.cache_backend = :rails
        c.cache_stale_while_revalidate = true
        c.cache_stale_ttl = 240
        c.cache_refresh_threads = 8
      end

      expect { config.validate! }.not_to raise_error

      expect(config.cache_ttl).to eq(120)
      expect(config.cache_stale_while_revalidate).to be true
      expect(config.cache_stale_ttl).to eq(240)
      expect(config.cache_refresh_threads).to eq(8)
    end

    it "maintains backward compatibility when SWR is disabled" do
      config = described_class.new do |c|
        c.public_key = "pk_test"
        c.secret_key = "sk_test"
        c.cache_ttl = 60
        c.cache_backend = :rails
        # SWR options not set - should use defaults
      end

      expect { config.validate! }.not_to raise_error

      expect(config.cache_stale_while_revalidate).to be false
      expect(config.cache_stale_ttl).to eq(300) # Default
      expect(config.cache_refresh_threads).to eq(5) # Default
    end
  end
end
