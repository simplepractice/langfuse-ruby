# frozen_string_literal: true

module Langfuse
  # Rails.cache adapter for distributed caching with Redis
  #
  # Wraps Rails.cache to provide distributed caching for prompts across
  # multiple processes and servers. Requires Rails with Redis cache store.
  #
  # @example
  #   adapter = Langfuse::RailsCacheAdapter.new(ttl: 60)
  #   adapter.set("greeting:1", prompt_data)
  #   adapter.get("greeting:1") # => prompt_data
  #
  class RailsCacheAdapter
    attr_reader :ttl, :namespace, :lock_timeout

    # Initialize a new Rails.cache adapter
    #
    # @param ttl [Integer] Time-to-live in seconds (default: 60)
    # @param namespace [String] Cache key namespace (default: "langfuse")
    # @param lock_timeout [Integer] Lock timeout in seconds for stampede protection (default: 10)
    # @raise [ConfigurationError] if Rails.cache is not available
    def initialize(ttl: 60, namespace: "langfuse", lock_timeout: 10)
      validate_rails_cache!

      @ttl = ttl
      @namespace = namespace
      @lock_timeout = lock_timeout
    end

    # Get a value from the cache
    #
    # @param key [String] Cache key
    # @return [Object, nil] Cached value or nil if not found/expired
    def get(key)
      Rails.cache.read(namespaced_key(key))
    end

    # Set a value in the cache
    #
    # @param key [String] Cache key
    # @param value [Object] Value to cache
    # @return [Object] The cached value
    def set(key, value)
      Rails.cache.write(namespaced_key(key), value, expires_in: ttl)
      value
    end

    # Fetch a value from cache with distributed lock for stampede protection
    #
    # This method prevents cache stampedes (thundering herd) by ensuring only one
    # process fetches from the source when the cache is empty. Other processes wait
    # for the first one to populate the cache.
    #
    # Uses exponential backoff: 50ms, 100ms, 200ms (3 retries max, ~350ms total).
    # If cache is still empty after waiting, falls back to fetching from source.
    #
    # @param key [String] Cache key
    # @yield Block to execute if cache miss (should fetch fresh data)
    # @return [Object] Cached or freshly fetched value
    #
    # @example
    #   adapter.fetch_with_lock("greeting:v1") do
    #     api_client.get_prompt("greeting")
    #   end
    def fetch_with_lock(key)
      # 1. Check cache first (fast path - no lock needed)
      cached = get(key)
      return cached if cached

      # 2. Cache miss - try to acquire distributed lock
      lock_key = "#{namespaced_key(key)}:lock"

      if acquire_lock(lock_key)
        begin
          # We got the lock - fetch from source and populate cache
          value = yield
          set(key, value)
          value
        ensure
          # Always release lock, even if block raises
          release_lock(lock_key)
        end
      else
        # Someone else has the lock - wait for them to populate cache
        cached = wait_for_cache(key)
        return cached if cached

        # Cache still empty after waiting - fall back to fetching ourselves
        # (This handles cases where lock holder crashed or took too long)
        yield
      end
    end

    # Clear the entire Langfuse cache namespace
    #
    # Note: This uses delete_matched which may not be available on all cache stores.
    # Works with Redis, Memcached, and memory stores. File store support varies.
    #
    # @return [void]
    def clear
      # Delete all keys matching the namespace pattern
      Rails.cache.delete_matched("#{namespace}:*")
    end

    # Get current cache size
    #
    # Note: Rails.cache doesn't provide a size method, so we return nil
    # to indicate this operation is not supported.
    #
    # @return [nil]
    def size
      nil
    end

    # Check if cache is empty
    #
    # Note: Rails.cache doesn't provide an efficient way to check if empty,
    # so we return nil to indicate this operation is not supported.
    #
    # @return [nil]
    def empty?
      nil
    end

    # Build a cache key from prompt name and options
    #
    # @param name [String] Prompt name
    # @param version [Integer, nil] Optional version
    # @param label [String, nil] Optional label
    # @return [String] Cache key
    def self.build_key(name, version: nil, label: nil)
      PromptCache.build_key(name, version: version, label: label)
    end

    private

    # Add namespace prefix to cache key
    #
    # @param key [String] Original cache key
    # @return [String] Namespaced cache key
    def namespaced_key(key)
      "#{namespace}:#{key}"
    end

    # Acquire a distributed lock using Rails.cache
    #
    # Uses atomic "write if not exists" operation to ensure only one process
    # can acquire the lock.
    #
    # @param lock_key [String] Full lock key (already namespaced)
    # @return [Boolean] true if lock was acquired, false if already held by another process
    def acquire_lock(lock_key)
      Rails.cache.write(
        lock_key,
        true,
        unless_exist: true, # Atomic: only write if key doesn't exist
        expires_in: lock_timeout # Auto-expire to prevent deadlocks
      )
    end

    # Release a distributed lock
    #
    # @param lock_key [String] Full lock key (already namespaced)
    # @return [void]
    def release_lock(lock_key)
      Rails.cache.delete(lock_key)
    end

    # Wait for cache to be populated by lock holder
    #
    # Uses exponential backoff: 50ms, 100ms, 200ms (3 retries, ~350ms total).
    # This gives the lock holder time to fetch and populate the cache.
    #
    # @param key [String] Cache key (not namespaced)
    # @return [Object, nil] Cached value if found, nil if still empty after waiting
    def wait_for_cache(key)
      intervals = [0.05, 0.1, 0.2] # 50ms, 100ms, 200ms (exponential backoff)

      intervals.each do |interval|
        sleep(interval)
        cached = get(key)
        return cached if cached
      end

      nil # Cache still empty after all retries
    end

    # Validate that Rails.cache is available
    #
    # @raise [ConfigurationError] if Rails.cache is not available
    # @return [void]
    def validate_rails_cache!
      return if defined?(Rails) && Rails.respond_to?(:cache)

      raise ConfigurationError,
            "Rails.cache is not available. Rails cache backend requires Rails with a configured cache store."
    end
  end
end
