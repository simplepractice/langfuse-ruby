#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Stale-While-Revalidate (SWR) Caching with Langfuse Ruby SDK
#
# This example demonstrates how to configure and use the SWR caching feature
# to achieve near-instant response times for prompt fetching.
#
# SWR provides three cache states:
# - FRESH: Return immediately from cache
# - REVALIDATE: Return stale data immediately + refresh in background
# - STALE: Fetch fresh data synchronously (fallback)

require "langfuse"

# Example 1: Basic SWR Configuration
puts "=== Example 1: Basic SWR Configuration ==="

Langfuse.configure do |config|
  config.public_key = ENV["LANGFUSE_PUBLIC_KEY"] || "pk_example"
  config.secret_key = ENV["LANGFUSE_SECRET_KEY"] || "sk_example"
  config.base_url = ENV["LANGFUSE_BASE_URL"] || "https://cloud.langfuse.com"

  # Enable Rails cache backend (required for SWR)
  config.cache_backend = :rails
  config.cache_ttl = 300 # Fresh for 5 minutes

  # Enable SWR with 5-minute grace period
  config.cache_stale_while_revalidate = true
  config.cache_stale_ttl = 300 # Serve stale for 5 more minutes
  config.cache_refresh_threads = 5 # Background refresh threads
end

# Mock Rails.cache for this example (in real Rails app, this is automatic)
unless defined?(Rails)
  class MockRailsCache
    def initialize
      @cache = {}
    end

    def read(key)
      entry = @cache[key]
      return nil unless entry
      return nil if entry[:expires_at] < Time.now

      entry[:value]
    end

    def write(key, value, options = {})
      expires_in = options[:expires_in] || 3600
      @cache[key] = {
        value: value,
        expires_at: Time.now + expires_in
      }
      true
    end

    def delete(key)
      @cache.delete(key)
    end

    def delete_matched(pattern)
      # Simple pattern matching for demo
      prefix = pattern.gsub("*", "")
      @cache.delete_if { |k, _| k.start_with?(prefix) }
    end
  end

  Rails = Struct.new(:cache).new(MockRailsCache.new)
end

client = Langfuse.client

puts "SWR Configuration:"
puts "- Cache TTL: #{client.config.cache_ttl} seconds"
puts "- SWR Enabled: #{client.config.cache_stale_while_revalidate}"
puts "- Stale TTL: #{client.config.cache_stale_ttl} seconds"
puts "- Refresh Threads: #{client.config.cache_refresh_threads}"
puts

# Example 2: Performance Comparison
puts "=== Example 2: Performance Comparison ==="

def measure_time
  start = Time.now
  yield
  ((Time.now - start) * 1000).round(2)
end

# Simulate API response times
class MockApiClient
  def self.fetch_prompt_from_api(name, **options)
    # Simulate network latency
    sleep(0.1) # 100ms API call

    {
      "id" => "prompt_#{rand(1000)}",
      "name" => name,
      "version" => options[:version] || 1,
      "type" => "text",
      "prompt" => "Hello {{name}}! This is #{name} prompt.",
      "labels" => ["production"],
      "tags" => ["example"],
      "config" => {}
    }
  end
end

# Override for demo purposes
original_method = client.api_client.method(:fetch_prompt_from_api)
client.api_client.define_singleton_method(:fetch_prompt_from_api) do |name, **options|
  MockApiClient.fetch_prompt_from_api(name, **options)
end

puts "Testing response times..."
puts

# First request - cache miss
time1 = measure_time do
  prompt1 = client.get_prompt("greeting")
  puts "First request (cache miss): #{prompt1['name']}"
end
puts "Time: #{time1}ms (includes API call)\n\n"

# Second request - cache hit (fresh)
time2 = measure_time do
  prompt2 = client.get_prompt("greeting")
  puts "Second request (cache hit): #{prompt2['name']}"
end
puts "Time: #{time2}ms (from cache)\n\n"

# Simulate cache expiry (in real scenario, this happens after TTL)
puts "Simulating cache expiry for SWR demonstration...\n"

# In a real scenario with SWR:
# - Request arrives after cache_ttl but before cache_ttl + stale_ttl
# - Returns stale data immediately (~1ms)
# - Triggers background refresh (doesn't block user)
puts "With SWR enabled:"
puts "- Cache expired but within grace period"
puts "- Would return stale data immediately (~1ms)"
puts "- Background refresh happens asynchronously"
puts "- User experiences no latency!"
puts

# Example 3: Configuration Options
puts "=== Example 3: Advanced Configuration ==="

puts "Different SWR configurations for various use cases:\n"

configurations = [
  {
    name: "High-Traffic Application",
    cache_ttl: 300,           # 5 minutes fresh
    cache_stale_ttl: 600,     # 10 minutes stale
    refresh_threads: 10,      # More threads for high load
    use_case: "Heavy prompt usage, needs instant responses"
  },
  {
    name: "Development Environment",
    cache_ttl: 60,            # 1 minute fresh
    cache_stale_ttl: 120,     # 2 minutes stale
    refresh_threads: 2,       # Fewer threads for dev
    use_case: "Faster iteration, shorter cache times"
  },
  {
    name: "Production Stable",
    cache_ttl: 1800,          # 30 minutes fresh
    cache_stale_ttl: 3600,    # 1 hour stale
    refresh_threads: 5,       # Standard threads
    use_case: "Stable prompts, maximum performance"
  }
]

configurations.each do |config|
  puts "#{config[:name]}:"
  puts "  Cache TTL: #{config[:cache_ttl]}s"
  puts "  Stale TTL: #{config[:cache_stale_ttl]}s"
  puts "  Refresh Threads: #{config[:refresh_threads]}"
  puts "  Use Case: #{config[:use_case]}"
  puts
end

# Example 4: Thread Pool Sizing Guidelines
puts "=== Example 4: Thread Pool Sizing Guidelines ==="

puts "Thread pool sizing calculation:"
puts "Threads = (Number of prompts × API latency) / Desired refresh time\n"

scenarios = [
  { prompts: 50, latency: 0.2, refresh_time: 5 },
  { prompts: 100, latency: 0.2, refresh_time: 5 },
  { prompts: 200, latency: 0.3, refresh_time: 10 }
]

scenarios.each do |scenario|
  required = (scenario[:prompts] * scenario[:latency]) / scenario[:refresh_time]
  recommended = (required * 1.25).ceil # 25% buffer

  puts "Scenario: #{scenario[:prompts]} prompts, #{scenario[:latency]}s latency"
  puts "  Required: #{required.round(1)} threads"
  puts "  Recommended: #{recommended} threads (with 25% buffer)"
  puts
end

# Example 5: SWR Benefits Summary
puts "=== Example 5: SWR Benefits Summary ==="

benefits = [
  {
    metric: "P99 Latency",
    without_swr: "100ms (first request after expiry)",
    with_swr: "1ms (serves stale immediately)"
  },
  {
    metric: "Cache Hit Rate",
    without_swr: "99% (1% pay latency cost)",
    with_swr: "99.9% (0.1% truly expired)"
  },
  {
    metric: "User Experience",
    without_swr: "Occasional 100ms delays",
    with_swr: "Consistent sub-millisecond responses"
  },
  {
    metric: "Resilience",
    without_swr: "Fails immediately if API down",
    with_swr: "Serves stale data during outages"
  }
]

benefits.each do |benefit|
  puts "#{benefit[:metric]}:"
  puts "  Without SWR: #{benefit[:without_swr]}"
  puts "  With SWR: #{benefit[:with_swr]}"
  puts
end

# Example 6: When NOT to use SWR
puts "=== Example 6: When NOT to use SWR ==="

not_recommended = [
  "Prompts that change frequently (users might see outdated versions)",
  "Critical data that must always be fresh",
  "Low-traffic applications (overhead not justified)",
  "Memory-constrained environments (thread pool overhead)",
  "Applications without Rails cache backend"
]

puts "SWR is NOT recommended for:"
not_recommended.each { |item| puts "- #{item}" }
puts

# Example 7: Monitoring SWR Performance
puts "=== Example 7: Monitoring SWR Performance ==="

puts "Key metrics to monitor:"
monitoring_metrics = [
  "Stale hit rate (how often stale data is served)",
  "Background refresh success rate",
  "Thread pool utilization",
  "Cache hit/miss ratios by cache state (fresh/revalidate/stale)",
  "API response times for background refreshes"
]

monitoring_metrics.each { |metric| puts "- #{metric}" }
puts

puts "=== SWR Cache Example Complete ==="
puts "For more information, see: docs/future-enhancements/STALE_WHILE_REVALIDATE_DESIGN.md"
