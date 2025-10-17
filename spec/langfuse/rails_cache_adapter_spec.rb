# frozen_string_literal: true

require "spec_helper"

RSpec.describe Langfuse::RailsCacheAdapter do
  # Mock Rails.cache for testing
  let(:mock_cache) { double("Rails.cache") }

  before do
    # Stub Rails constant and cache
    rails_class = Class.new do
      def self.cache
        @cache ||= nil
      end

      class << self
        attr_writer :cache
      end
    end

    stub_const("Rails", rails_class)
    Rails.cache = mock_cache
  end

  describe "#initialize" do
    context "when Rails.cache is available" do
      it "creates an adapter with default TTL" do
        adapter = described_class.new
        expect(adapter.ttl).to eq(60)
        expect(adapter.namespace).to eq("langfuse")
      end

      it "creates an adapter with custom TTL" do
        adapter = described_class.new(ttl: 120)
        expect(adapter.ttl).to eq(120)
      end

      it "creates an adapter with custom namespace" do
        adapter = described_class.new(namespace: "my_app")
        expect(adapter.namespace).to eq("my_app")
      end
    end

    context "when Rails.cache is not available" do
      before do
        hide_const("Rails")
      end

      it "raises ConfigurationError" do
        expect do
          described_class.new
        end.to raise_error(
          Langfuse::ConfigurationError,
          /Rails.cache is not available/
        )
      end
    end

    context "when Rails is defined but cache is not available" do
      before do
        rails_without_cache = Class.new
        stub_const("Rails", rails_without_cache)
      end

      it "raises ConfigurationError" do
        expect do
          described_class.new
        end.to raise_error(
          Langfuse::ConfigurationError,
          /Rails.cache is not available/
        )
      end
    end
  end

  describe "#get" do
    let(:adapter) { described_class.new(ttl: 60) }

    it "reads from Rails.cache with namespaced key" do
      expect(mock_cache).to receive(:read).with("langfuse:greeting:v1").and_return({ "name" => "greeting" })

      result = adapter.get("greeting:v1")
      expect(result).to eq({ "name" => "greeting" })
    end

    it "returns nil when key not found" do
      expect(mock_cache).to receive(:read).with("langfuse:missing").and_return(nil)

      result = adapter.get("missing")
      expect(result).to be_nil
    end

    it "uses custom namespace" do
      custom_adapter = described_class.new(namespace: "custom")
      expect(mock_cache).to receive(:read).with("custom:key").and_return("value")

      custom_adapter.get("key")
    end
  end

  describe "#set" do
    let(:adapter) { described_class.new(ttl: 120) }

    it "writes to Rails.cache with namespaced key and TTL" do
      data = { "name" => "greeting", "prompt" => "Hello!" }
      expect(mock_cache).to receive(:write).with(
        "langfuse:greeting:v1",
        data,
        expires_in: 120
      ).and_return(true)

      result = adapter.set("greeting:v1", data)
      expect(result).to eq(data)
    end

    it "returns the cached value" do
      expect(mock_cache).to receive(:write).and_return(true)

      result = adapter.set("key", "value")
      expect(result).to eq("value")
    end

    it "uses custom namespace and TTL" do
      custom_adapter = described_class.new(ttl: 300, namespace: "custom")
      expect(mock_cache).to receive(:write).with(
        "custom:key",
        "value",
        expires_in: 300
      ).and_return(true)

      custom_adapter.set("key", "value")
    end
  end

  describe "#clear" do
    let(:adapter) { described_class.new }

    it "deletes all keys matching namespace pattern" do
      expect(mock_cache).to receive(:delete_matched).with("langfuse:*")

      adapter.clear
    end

    it "uses custom namespace for pattern" do
      custom_adapter = described_class.new(namespace: "custom")
      expect(mock_cache).to receive(:delete_matched).with("custom:*")

      custom_adapter.clear
    end
  end

  describe "#size" do
    let(:adapter) { described_class.new }

    it "returns nil (not supported by Rails.cache)" do
      expect(adapter.size).to be_nil
    end
  end

  describe "#empty?" do
    let(:adapter) { described_class.new }

    it "returns nil (not supported by Rails.cache)" do
      expect(adapter.empty?).to be_nil
    end
  end

  describe ".build_key" do
    it "delegates to PromptCache.build_key" do
      expect(Langfuse::PromptCache).to receive(:build_key).with(
        "greeting",
        version: 1,
        label: nil
      ).and_return("greeting:v1")

      key = described_class.build_key("greeting", version: 1)
      expect(key).to eq("greeting:v1")
    end

    it "builds key with name only" do
      key = described_class.build_key("greeting")
      expect(key).to eq("greeting")
    end

    it "builds key with name and version" do
      key = described_class.build_key("greeting", version: 2)
      expect(key).to eq("greeting:v2")
    end

    it "builds key with name and label" do
      key = described_class.build_key("greeting", label: "production")
      expect(key).to eq("greeting:production")
    end

    it "builds key with all parameters" do
      key = described_class.build_key("greeting", version: 3, label: "staging")
      expect(key).to eq("greeting:v3:staging")
    end
  end

  describe "integration with cache interface" do
    let(:adapter) { described_class.new(ttl: 60) }

    it "implements the same interface as PromptCache" do
      # Should respond to all public methods that PromptCache has
      expect(adapter).to respond_to(:get)
      expect(adapter).to respond_to(:set)
      expect(adapter).to respond_to(:clear)
      expect(adapter).to respond_to(:size)
      expect(adapter).to respond_to(:empty?)
      expect(described_class).to respond_to(:build_key)
    end

    it "can be used interchangeably with PromptCache" do
      # Simulate the pattern used in ApiClient
      cache = adapter
      cache_key = described_class.build_key("greeting", version: 1)

      # Mock Rails.cache operations
      expect(mock_cache).to receive(:read).with("langfuse:greeting:v1").and_return(nil)
      expect(mock_cache).to receive(:write).with(
        "langfuse:greeting:v1",
        { "data" => "test" },
        expires_in: 60
      ).and_return(true)

      # Check cache (miss)
      cached = cache.get(cache_key)
      expect(cached).to be_nil

      # Set cache
      cache.set(cache_key, { "data" => "test" })

      # Mock successful read
      expect(mock_cache).to receive(:read).with("langfuse:greeting:v1").and_return({ "data" => "test" })

      # Check cache (hit)
      cached = cache.get(cache_key)
      expect(cached).to eq({ "data" => "test" })
    end
  end

  describe "#fetch_with_lock" do
    let(:adapter) { described_class.new(ttl: 120, lock_timeout: 5) }
    let(:cache_key) { "greeting:v1" }
    let(:lock_key) { "langfuse:greeting:v1:lock" }
    let(:namespaced_key) { "langfuse:greeting:v1" }

    context "when cache hit" do
      it "returns cached value without acquiring lock" do
        expect(mock_cache).to receive(:read).with(namespaced_key).and_return({ "cached" => "data" })

        result = adapter.fetch_with_lock(cache_key) do
          raise "Block should not be called on cache hit!"
        end

        expect(result).to eq({ "cached" => "data" })
      end

      it "does not execute the block" do
        expect(mock_cache).to receive(:read).with(namespaced_key).and_return({ "cached" => "data" })

        block_executed = false
        adapter.fetch_with_lock(cache_key) do
          block_executed = true
        end

        expect(block_executed).to be false
      end
    end

    context "when cache miss and lock acquired" do
      it "executes block and populates cache" do
        # Cache miss
        expect(mock_cache).to receive(:read).with(namespaced_key).and_return(nil)

        # Lock acquisition succeeds
        expect(mock_cache).to receive(:write).with(
          lock_key,
          true,
          unless_exist: true,
          expires_in: 5
        ).and_return(true)

        # Set cache with result
        expect(mock_cache).to receive(:write).with(
          namespaced_key,
          { "fresh" => "data" },
          expires_in: 120
        ).and_return(true)

        # Release lock
        expect(mock_cache).to receive(:delete).with(lock_key)

        result = adapter.fetch_with_lock(cache_key) do
          { "fresh" => "data" }
        end

        expect(result).to eq({ "fresh" => "data" })
      end

      it "releases lock even if block raises error" do
        expect(mock_cache).to receive(:read).with(namespaced_key).and_return(nil)
        expect(mock_cache).to receive(:write).with(
          lock_key,
          true,
          unless_exist: true,
          expires_in: 5
        ).and_return(true)

        # Lock should still be released even if block fails
        expect(mock_cache).to receive(:delete).with(lock_key)

        expect do
          adapter.fetch_with_lock(cache_key) do
            raise StandardError, "Simulated API error"
          end
        end.to raise_error(StandardError, "Simulated API error")
      end
    end

    context "when cache miss and lock NOT acquired (someone else has it)" do
      it "waits and returns cached value if available" do
        # Cache miss initially
        expect(mock_cache).to receive(:read).with(namespaced_key).and_return(nil)

        # Lock acquisition fails (someone else has it)
        expect(mock_cache).to receive(:write).with(
          lock_key,
          true,
          unless_exist: true,
          expires_in: 5
        ).and_return(false)

        # Wait with exponential backoff (3 retries)
        # First retry (50ms) - still empty
        expect(mock_cache).to receive(:read).with(namespaced_key).and_return(nil)

        # Second retry (100ms) - populated!
        expect(mock_cache).to receive(:read).with(namespaced_key).and_return({ "populated" => "by lock holder" })

        result = adapter.fetch_with_lock(cache_key) do
          raise "Block should not execute - cache was populated by lock holder"
        end

        expect(result).to eq({ "populated" => "by lock holder" })
      end

      it "falls back to fetching if cache still empty after waiting" do
        # Cache miss initially
        expect(mock_cache).to receive(:read).with(namespaced_key).and_return(nil)

        # Lock acquisition fails
        expect(mock_cache).to receive(:write).with(
          lock_key,
          true,
          unless_exist: true,
          expires_in: 5
        ).and_return(false)

        # Wait with 3 retries - all return nil (cache still empty)
        expect(mock_cache).to receive(:read).with(namespaced_key).and_return(nil).exactly(3).times

        # Block should execute as fallback
        result = adapter.fetch_with_lock(cache_key) do
          { "fallback" => "fetch" }
        end

        expect(result).to eq({ "fallback" => "fetch" })
      end

      it "uses exponential backoff when waiting" do
        expect(mock_cache).to receive(:read).with(namespaced_key).and_return(nil)
        expect(mock_cache).to receive(:write).and_return(false) # Lock not acquired

        # All retries return nil
        expect(mock_cache).to receive(:read).with(namespaced_key).and_return(nil).exactly(3).times

        start_time = Time.now

        adapter.fetch_with_lock(cache_key) do
          { "data" => "test" }
        end

        elapsed = Time.now - start_time

        # Should sleep for 0.05 + 0.1 + 0.2 = 0.35 seconds
        # Allow some tolerance for test execution time
        expect(elapsed).to be >= 0.30 # At least 300ms
        expect(elapsed).to be < 0.50  # Less than 500ms (with buffer)
      end
    end

    context "with custom lock timeout" do
      let(:custom_adapter) { described_class.new(ttl: 60, lock_timeout: 15) }

      it "uses custom lock timeout when acquiring lock" do
        expect(mock_cache).to receive(:read).with(namespaced_key).and_return(nil)
        expect(mock_cache).to receive(:write).with(
          lock_key,
          true,
          unless_exist: true,
          expires_in: 15 # Custom timeout
        ).and_return(true)

        expect(mock_cache).to receive(:write).with(namespaced_key, anything, expires_in: 60).and_return(true)
        expect(mock_cache).to receive(:delete).with(lock_key)

        custom_adapter.fetch_with_lock(cache_key) do
          { "data" => "test" }
        end
      end
    end
  end

  describe "stampede protection behavior" do
    let(:adapter) { described_class.new(ttl: 60) }

    it "responds to fetch_with_lock" do
      expect(adapter).to respond_to(:fetch_with_lock)
    end

    it "provides distributed lock capability not available in PromptCache" do
      memory_cache = Langfuse::PromptCache.new(ttl: 60)
      rails_cache = adapter

      expect(memory_cache).not_to respond_to(:fetch_with_lock)
      expect(rails_cache).to respond_to(:fetch_with_lock)
    end
  end
end
