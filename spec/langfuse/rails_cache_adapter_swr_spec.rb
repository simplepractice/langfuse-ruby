# frozen_string_literal: true

require "spec_helper"

RSpec.describe Langfuse::RailsCacheAdapter do
  let(:ttl) { 60 }
  let(:stale_ttl) { 120 }
  let(:refresh_threads) { 2 }

  let(:adapter_with_swr) do
    described_class.new(
      ttl: ttl,
      stale_ttl: stale_ttl,
      refresh_threads: refresh_threads
    )
  end

  let(:adapter_without_swr) do
    described_class.new(ttl: ttl)
  end

  # Mock Rails.cache for testing
  let(:rails_cache) { double("Rails.cache") }

  before do
    stub_const("Rails", double("Rails", cache: rails_cache))
    allow(rails_cache).to receive(:read).and_return(nil)
    allow(rails_cache).to receive(:write).and_return(true)
    allow(rails_cache).to receive(:delete).and_return(true)
    allow(rails_cache).to receive(:delete_matched).and_return(true)
  end

  describe "#initialize" do
    context "with SWR enabled" do
      it "creates a thread pool" do
        expect(adapter_with_swr.thread_pool).not_to be_nil
        expect(adapter_with_swr.stale_ttl).to eq(stale_ttl)
      end
    end

    context "without SWR" do
      it "does not create a thread pool" do
        expect(adapter_without_swr.thread_pool).to be_nil
      end
    end
  end

  describe "#fetch_with_stale_while_revalidate" do
    let(:cache_key) { "test_key" }
    let(:fresh_data) { "fresh_value" }
    let(:stale_data) { "stale_value" }
    let(:new_data) { "new_value" }

    context "when SWR is disabled" do
      it "falls back to fetch_with_lock" do
        expect(adapter_without_swr).to receive(:fetch_with_lock).with(cache_key)
        adapter_without_swr.fetch_with_stale_while_revalidate(cache_key) { new_data }
      end
    end

    context "with fresh cache entry" do
      let(:fresh_entry) do
        {
          data: fresh_data,
          fresh_until: Time.now + 30,
          stale_until: Time.now + 150
        }
      end

      before do
        allow(adapter_with_swr).to receive(:get_entry_with_metadata)
          .with(cache_key)
          .and_return(fresh_entry)
      end

      it "returns cached data immediately" do
        result = adapter_with_swr.fetch_with_stale_while_revalidate(cache_key) { new_data }
        expect(result).to eq(fresh_data)
      end

      it "does not trigger background refresh" do
        expect(adapter_with_swr).not_to receive(:schedule_refresh)
        adapter_with_swr.fetch_with_stale_while_revalidate(cache_key) { new_data }
      end
    end

    context "with stale entry (revalidate state)" do
      let(:stale_entry) do
        {
          data: stale_data,
          fresh_until: Time.now - 30, # Expired
          stale_until: Time.now + 90  # Still within grace period
        }
      end

      before do
        allow(adapter_with_swr).to receive(:get_entry_with_metadata)
          .with(cache_key)
          .and_return(stale_entry)
      end

      it "returns stale data immediately" do
        allow(adapter_with_swr).to receive(:schedule_refresh)

        result = adapter_with_swr.fetch_with_stale_while_revalidate(cache_key) { new_data }
        expect(result).to eq(stale_data)
      end

      it "schedules background refresh" do
        expect(adapter_with_swr).to receive(:schedule_refresh).with(cache_key)

        adapter_with_swr.fetch_with_stale_while_revalidate(cache_key) { new_data }
      end
    end

    context "with expired entry (past stale period)" do
      let(:expired_entry) do
        {
          data: stale_data,
          fresh_until: Time.now - 150, # Expired
          stale_until: Time.now - 30   # Past grace period
        }
      end

      before do
        allow(adapter_with_swr).to receive(:get_entry_with_metadata)
          .with(cache_key)
          .and_return(expired_entry)
        allow(adapter_with_swr).to receive(:fetch_and_cache_with_metadata)
          .with(cache_key)
          .and_return(new_data)
      end

      it "fetches fresh data synchronously" do
        expect(adapter_with_swr).to receive(:fetch_and_cache_with_metadata)
          .with(cache_key)
          .and_return(new_data)

        result = adapter_with_swr.fetch_with_stale_while_revalidate(cache_key) { new_data }
        expect(result).to eq(new_data)
      end

      it "does not schedule background refresh" do
        expect(adapter_with_swr).not_to receive(:schedule_refresh)
        adapter_with_swr.fetch_with_stale_while_revalidate(cache_key) { new_data }
      end
    end

    context "with cache miss" do
      before do
        allow(adapter_with_swr).to receive(:get_entry_with_metadata)
          .with(cache_key)
          .and_return(nil)
        allow(adapter_with_swr).to receive(:fetch_and_cache_with_metadata)
          .with(cache_key)
          .and_return(new_data)
      end

      it "fetches fresh data synchronously" do
        expect(adapter_with_swr).to receive(:fetch_and_cache_with_metadata)
          .with(cache_key)
          .and_return(new_data)

        result = adapter_with_swr.fetch_with_stale_while_revalidate(cache_key) { new_data }
        expect(result).to eq(new_data)
      end
    end
  end

  describe "#schedule_refresh" do
    let(:cache_key) { "test_key" }
    let(:refresh_lock_key) { "langfuse:#{cache_key}:refreshing" }
    let(:new_data) { "refreshed_value" }

    context "when refresh lock is acquired" do
      before do
        allow(adapter_with_swr).to receive(:acquire_refresh_lock)
          .with(refresh_lock_key)
          .and_return(true)
        allow(adapter_with_swr).to receive(:set_with_metadata)
        allow(adapter_with_swr).to receive(:release_lock)
      end

      it "schedules refresh in thread pool" do
        # Mock thread pool to execute immediately for testing
        allow(adapter_with_swr.thread_pool).to receive(:post).and_yield

        expect(adapter_with_swr).to receive(:set_with_metadata)
          .with(cache_key, new_data)

        adapter_with_swr.send(:schedule_refresh, cache_key) { new_data }
      end

      it "releases the refresh lock after completion" do
        allow(adapter_with_swr.thread_pool).to receive(:post).and_yield

        expect(adapter_with_swr).to receive(:release_lock)
          .with(refresh_lock_key)

        adapter_with_swr.send(:schedule_refresh, cache_key) { new_data }
      end

      it "releases the refresh lock even if block raises" do
        allow(adapter_with_swr.thread_pool).to receive(:post).and_yield

        expect(adapter_with_swr).to receive(:release_lock)
          .with(refresh_lock_key)

        expect do
          adapter_with_swr.send(:schedule_refresh, cache_key) { raise "test error" }
        end.to raise_error("test error")
      end
    end

    context "when refresh lock is not acquired" do
      before do
        allow(adapter_with_swr).to receive(:acquire_refresh_lock)
          .with(refresh_lock_key)
          .and_return(false)
      end

      it "does not schedule refresh" do
        expect(adapter_with_swr.thread_pool).not_to receive(:post)
        adapter_with_swr.send(:schedule_refresh, cache_key) { new_data }
      end
    end
  end

  describe "#get_entry_with_metadata" do
    let(:cache_key) { "test_key" }
    let(:namespaced_metadata_key) { "langfuse:#{cache_key}:metadata" }

    context "when metadata exists" do
      let(:fresh_until_time) { Time.now + 30 }
      let(:stale_until_time) { Time.now + 150 }
      let(:metadata_json) do
        {
          data: "test_value",
          fresh_until: fresh_until_time.to_s,
          stale_until: stale_until_time.to_s
        }.to_json
      end

      before do
        allow(rails_cache).to receive(:read)
          .with(namespaced_metadata_key)
          .and_return(metadata_json)
      end

      it "returns parsed metadata with symbolized keys" do
        result = adapter_with_swr.send(:get_entry_with_metadata, cache_key)

        expect(result).to be_a(Hash)
        expect(result[:data]).to eq("test_value")
        expect(result[:fresh_until]).to be_a(Time)
        expect(result[:stale_until]).to be_a(Time)
      end
    end

    context "when metadata does not exist" do
      before do
        allow(rails_cache).to receive(:read)
          .with(namespaced_metadata_key)
          .and_return(nil)
      end

      it "returns nil" do
        result = adapter_with_swr.send(:get_entry_with_metadata, cache_key)
        expect(result).to be_nil
      end
    end

    context "when metadata is invalid JSON" do
      before do
        allow(rails_cache).to receive(:read)
          .with(namespaced_metadata_key)
          .and_return("invalid json")
      end

      it "returns nil" do
        result = adapter_with_swr.send(:get_entry_with_metadata, cache_key)
        expect(result).to be_nil
      end
    end
  end

  describe "#set_with_metadata" do
    let(:cache_key) { "test_key" }
    let(:value) { "test_value" }
    let(:namespaced_key) { "langfuse:#{cache_key}" }
    let(:namespaced_metadata_key) { "langfuse:#{cache_key}:metadata" }
    let(:total_ttl) { ttl + stale_ttl }

    it "stores both value and metadata with correct TTL" do
      freeze_time = Time.now
      allow(Time).to receive(:now).and_return(freeze_time)

      expect(rails_cache).to receive(:write)
        .with(namespaced_key, value, expires_in: total_ttl)

      expect(rails_cache).to receive(:write)
        .with(namespaced_metadata_key, anything, expires_in: total_ttl)

      result = adapter_with_swr.send(:set_with_metadata, cache_key, value)
      expect(result).to eq(value)
    end

    it "stores metadata with correct timestamps" do
      freeze_time = Time.now
      allow(Time).to receive(:now).and_return(freeze_time)

      expected_metadata = {
        data: value,
        fresh_until: freeze_time + ttl,
        stale_until: freeze_time + ttl + stale_ttl
      }.to_json

      expect(rails_cache).to receive(:write)
        .with(namespaced_metadata_key, expected_metadata, expires_in: total_ttl)

      adapter_with_swr.send(:set_with_metadata, cache_key, value)
    end
  end

  describe "#acquire_refresh_lock" do
    let(:lock_key) { "langfuse:test_key:refreshing" }

    context "when lock is available" do
      before do
        allow(rails_cache).to receive(:write)
          .with(lock_key, true, unless_exist: true, expires_in: 60)
          .and_return(true)
      end

      it "acquires the lock and returns true" do
        result = adapter_with_swr.send(:acquire_refresh_lock, lock_key)
        expect(result).to be true
      end
    end

    context "when lock is already held" do
      before do
        allow(rails_cache).to receive(:write)
          .with(lock_key, true, unless_exist: true, expires_in: 60)
          .and_return(false)
      end

      it "fails to acquire lock and returns false" do
        result = adapter_with_swr.send(:acquire_refresh_lock, lock_key)
        expect(result).to be false
      end
    end
  end

  describe "#shutdown" do
    it "shuts down the thread pool gracefully" do
      thread_pool = adapter_with_swr.thread_pool
      expect(thread_pool).to receive(:shutdown).once
      expect(thread_pool).to receive(:wait_for_termination).with(5).once

      adapter_with_swr.shutdown
    end

    context "when no thread pool exists" do
      it "does not raise an error" do
        expect { adapter_without_swr.shutdown }.not_to raise_error
      end
    end
  end

  # Integration test: full SWR cycle
  describe "SWR integration" do
    let(:cache_key) { "integration_test" }
    let(:initial_value) { "initial" }
    let(:updated_value) { "updated" }

    # Use a real in-memory cache for this test
    let(:memory_cache) { {} }

    before do
      # Mock Rails.cache with a simple hash
      allow(rails_cache).to receive(:read) { |key| memory_cache[key] }
      allow(rails_cache).to receive(:write) do |key, value, _options|
        memory_cache[key] = value
        true
      end
      allow(rails_cache).to receive(:delete) { |key| memory_cache.delete(key) }
    end

    it "handles complete SWR lifecycle" do
      fetch_count = 0
      fetch_proc = proc do
        fetch_count += 1
        fetch_count == 1 ? initial_value : updated_value
      end

      # 1. First fetch - cache miss, should fetch and cache
      result1 = adapter_with_swr.fetch_with_stale_while_revalidate(cache_key, &fetch_proc)
      expect(result1).to eq(initial_value)
      expect(fetch_count).to eq(1)

      # 2. Simulate time passing to make entry stale but not expired
      # Mock thread pool to execute immediately
      allow(adapter_with_swr.thread_pool).to receive(:post).and_yield

      # Simulate the cache entry being in stale state by directly manipulating the metadata
      stale_entry = {
        data: initial_value,
        fresh_until: (Time.now - 30).to_s, # Past fresh time
        stale_until: (Time.now + 90).to_s # Still within stale period
      }

      memory_cache["langfuse:#{cache_key}:metadata"] = stale_entry.to_json

      result2 = adapter_with_swr.fetch_with_stale_while_revalidate(cache_key, &fetch_proc)

      # Should return stale data immediately
      expect(result2).to eq(initial_value)

      # Should have triggered background refresh
      expect(fetch_count).to eq(2)

      # 3. Next request should get updated data (simulate fresh cache after background refresh)
      fresh_entry = {
        data: updated_value,
        fresh_until: (Time.now + 60).to_s,
        stale_until: (Time.now + 150).to_s
      }
      memory_cache["langfuse:#{cache_key}"] = updated_value
      memory_cache["langfuse:#{cache_key}:metadata"] = fresh_entry.to_json

      result3 = adapter_with_swr.fetch_with_stale_while_revalidate(cache_key, &fetch_proc)
      expect(result3).to eq(updated_value)
      # Should not fetch again (using cached updated value)
      expect(fetch_count).to eq(2)
    end
  end
end
