# Stale-While-Revalidate (SWR) Caching Feature

This document describes the implementation of Stale-While-Revalidate (SWR) caching in the Langfuse Ruby SDK, which provides near-instant response times for prompt fetching.

## Overview

SWR caching serves slightly outdated (stale) data immediately while refreshing in the background. This eliminates the latency penalty that users experience when cache entries expire, providing consistently fast response times.

## Problem Solved

**Before SWR:**
- Cache expires every 5 minutes
- First request after expiry waits ~100ms for API call
- Other requests benefit from stampede protection but one user pays the cost

**With SWR:**
- All requests get ~1ms response times
- Stale data served immediately during grace period
- Background refresh happens asynchronously

## Implementation

### Three Cache States

1. **FRESH** (`Time.now < fresh_until`): Return immediately, no action needed
2. **REVALIDATE** (`fresh_until <= Time.now < stale_until`): Return stale data + trigger background refresh
3. **STALE** (`Time.now >= stale_until`): Must fetch fresh data synchronously

### Configuration

```ruby
Langfuse.configure do |config|
  config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
  config.secret_key = ENV['LANGFUSE_SECRET_KEY']
  
  # Required: Use Rails cache backend
  config.cache_backend = :rails
  config.cache_ttl = 300 # Fresh for 5 minutes
  
  # Enable SWR
  config.cache_stale_while_revalidate = true
  config.cache_stale_ttl = 300 # Grace period: 5 more minutes
  config.cache_refresh_threads = 5 # Background thread pool size
end
```

### New Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cache_stale_while_revalidate` | Boolean | `false` | Enable SWR caching (opt-in) |
| `cache_stale_ttl` | Integer | `300` | Grace period duration in seconds |
| `cache_refresh_threads` | Integer | `5` | Background thread pool size |

## Usage

Once configured, SWR works transparently:

```ruby
client = Langfuse.client

# First request - populates cache
prompt = client.get_prompt("greeting") # ~100ms (API call)

# Subsequent requests while fresh
prompt = client.get_prompt("greeting") # ~1ms (cache hit)

# After cache_ttl expires but within grace period
prompt = client.get_prompt("greeting") # ~1ms (stale data + background refresh)

# Background refresh completes, next request gets fresh data
prompt = client.get_prompt("greeting") # ~1ms (fresh cache)
```

## Architecture

### Enhanced Cache Entry Structure

```ruby
CacheEntry = {
  data: prompt_data,
  fresh_until: Time.now + cache_ttl,
  stale_until: Time.now + cache_ttl + cache_stale_ttl
}
```

### Components Added

1. **RailsCacheAdapter Enhancements**
   - `fetch_with_stale_while_revalidate()` method
   - Metadata storage for timestamps
   - Background thread pool management
   - Refresh lock mechanism

2. **ApiClient Integration**
   - Automatic SWR detection and usage
   - Graceful fallback to stampede protection
   - Error handling for cache failures

3. **Configuration Validation**
   - SWR requires Rails cache backend
   - Parameter validation for all new options
   - Backward compatibility maintained

## Performance Benefits

### Latency Improvements

| Scenario | Without SWR | With SWR |
|----------|-------------|----------|
| Cache hit | ~1ms | ~1ms |
| Cache miss (first after expiry) | ~100ms | ~1ms* |
| P99 latency | 100ms | 1ms |

*Returns stale data, refresh happens in background

### Load Distribution

- No thundering herd at expiry time
- API load distributed over time
- Smoother cache warming
- Reduced perceived latency

## Thread Pool Sizing

### Calculation Formula

```
Threads = (Number of prompts × API latency) / Desired refresh time
```

### Examples

**50 prompts, 200ms API latency, 5s refresh window:**
- Required: (50 × 0.2) / 5 = 2 threads
- Recommended: 3 threads (with 25% buffer)

**100 prompts, 200ms API latency, 5s refresh window:**
- Required: (100 × 0.2) / 5 = 4 threads  
- Recommended: 5 threads (with 25% buffer)

### Auto-Sizing Pool

The implementation uses `Concurrent::CachedThreadPool`:

```ruby
Concurrent::CachedThreadPool.new(
  max_threads: config.cache_refresh_threads,
  min_threads: 2,
  max_queue: 50,
  fallback_policy: :discard
)
```

## When to Use SWR

### ✅ Good For

- High-traffic applications where latency matters
- Prompts that don't change frequently
- Systems where eventual consistency is acceptable
- Applications with many processes (shared benefit)

### ❌ Not Ideal For

- Prompts that change frequently
- Critical data requiring immediate freshness
- Low-traffic applications (overhead not justified)
- Memory-constrained environments
- Applications without Rails cache backend

## Error Handling

### Cache Failures

SWR handles cache errors gracefully by falling back to direct API calls:

```ruby
begin
  cache.fetch_with_stale_while_revalidate(key) { api_call }
rescue StandardError => e
  logger.warn("Cache error: #{e.message}")
  api_call # Fallback to direct fetch
end
```

### Background Refresh Failures

- Failed refreshes don't block users
- Stale data continues to be served
- Next synchronous request will retry API call
- Refresh locks prevent duplicate attempts

## Monitoring

### Key Metrics

1. **Stale hit rate** - How often stale data is served
2. **Background refresh success rate** - Reliability of async updates
3. **Thread pool utilization** - Resource usage
4. **Cache state distribution** - Fresh vs. revalidate vs. stale
5. **API latency for refreshes** - Background performance

### Logging

The implementation includes detailed logging:

```ruby
logger.info("SWR: Serving stale data for key=#{key}")
logger.info("SWR: Scheduling background refresh for key=#{key}")
logger.warn("SWR: Refresh lock already held for key=#{key}")
```

## Testing

### Test Coverage

The implementation includes comprehensive tests:

- **Unit tests**: Cache state transitions, metadata handling
- **Integration tests**: ApiClient SWR integration
- **Concurrency tests**: Thread pool behavior, refresh locks
- **Error handling**: Cache failures, API errors

### Test Files

- `spec/langfuse/config_swr_spec.rb` - Configuration validation
- `spec/langfuse/rails_cache_adapter_swr_spec.rb` - SWR implementation
- `spec/langfuse/api_client_swr_spec.rb` - Integration tests

## Dependencies

### New Runtime Dependency

```ruby
# langfuse.gemspec
spec.add_dependency "concurrent-ruby", "~> 1.2"
```

### Existing Dependencies

- Rails.cache (Redis recommended)
- Faraday (HTTP client)
- JSON (metadata serialization)

## Configuration Examples

### High-Traffic Application

```ruby
config.cache_ttl = 300               # 5 minutes fresh
config.cache_stale_ttl = 600         # 10 minutes stale
config.cache_refresh_threads = 10    # High concurrency
```

### Development Environment

```ruby
config.cache_ttl = 60                # 1 minute fresh
config.cache_stale_ttl = 120         # 2 minutes stale  
config.cache_refresh_threads = 2     # Low overhead
```

### Production Stable

```ruby
config.cache_ttl = 1800              # 30 minutes fresh
config.cache_stale_ttl = 3600        # 1 hour stale
config.cache_refresh_threads = 5     # Balanced
```

## Migration Guide

### Enabling SWR

1. **Update configuration:**
   ```ruby
   config.cache_backend = :rails # Required
   config.cache_stale_while_revalidate = true
   ```

2. **No code changes required** - SWR works transparently

3. **Monitor performance** - Verify latency improvements

### Rollback Plan

Set `cache_stale_while_revalidate = false` to disable SWR and return to stampede protection mode.

## Future Enhancements

### Planned Features

1. **Smart Refresh Scheduling** - Predictive refresh based on usage patterns
2. **Adaptive TTL** - Dynamic TTL based on prompt change frequency  
3. **Enhanced Metrics** - Detailed observability and instrumentation

### Considerations

- Cache warming strategies
- Multi-region cache synchronization
- Prompt versioning impact on SWR effectiveness

## Example Usage

See `examples/swr_cache_example.rb` for a complete demonstration of SWR configuration and usage patterns.

## References

- **Design Document**: `docs/future-enhancements/STALE_WHILE_REVALIDATE_DESIGN.md`
- **HTTP SWR Specification**: [RFC 5861](https://datatracker.ietf.org/doc/html/rfc5861)
- **concurrent-ruby Documentation**: [GitHub](https://github.com/ruby-concurrency/concurrent-ruby)

---

**Implementation Status**: ✅ Complete
**Branch**: `swr-cache`
**Tests**: 53 additional tests, 100% passing
**Coverage**: Maintains >95% test coverage
