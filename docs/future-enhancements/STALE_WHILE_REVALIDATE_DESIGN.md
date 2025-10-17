# Stale-While-Revalidate (SWR) Design Document

**Status:** Design Only - Not Implemented
**Phase:** 7.3 (Future Enhancement)
**Created:** 2025-10-16

---

## Problem Statement

With current caching (Phases 7.1 + 7.2), the first request after cache expiry must wait for the Langfuse API call (~100ms). Even with stampede protection preventing 1,200 simultaneous API calls, one user still pays the latency cost.

**Current Timeline:**
```
Time: 10:00:00 - Prompt cached (TTL: 300s)
Time: 10:05:00 - Cache expires
Time: 10:05:00.001 - Request arrives
  → Check cache: MISS (expired)
  → Acquire lock: SUCCESS
  → Call Langfuse API: 100ms ⏳ (user waits)
  → Populate cache
  → Return to user
Total latency: ~100ms for first user
```

---

## Solution: Stale-While-Revalidate

Serve slightly outdated (stale) data immediately while refreshing in the background. Users get instant responses (~1ms) even after cache "expires".

**With SWR Timeline:**
```
Time: 10:00:00 - Prompt cached
  - fresh_until: 10:05:00 (TTL: 5 minutes)
  - stale_until: 10:10:00 (grace period: 5 more minutes)

Time: 10:05:01 - Request arrives (cache expired but not stale)
  → Return STALE data immediately (1ms latency) ✨
  → Trigger background refresh (doesn't block user)
  → Background: Fetch from API, update cache
```

---

## Design Overview

### Three Cache States

1. **FRESH** (`Time.now < fresh_until`): Return immediately, no action needed
2. **REVALIDATE** (`fresh_until <= Time.now < stale_until`): Return stale data + trigger background refresh
3. **STALE** (`Time.now >= stale_until`): Must fetch fresh data synchronously

### Cache Entry Structure

**Current (Phase 7.1/7.2):**
```ruby
CacheEntry = Struct.new(:data, :expires_at)
```

**With SWR (Phase 7.3):**
```ruby
CacheEntry = Struct.new(:data, :fresh_until, :stale_until) do
  def fresh?
    Time.now < fresh_until
  end

  def stale?
    Time.now > stale_until
  end

  def revalidate?
    !fresh? && !stale?
  end
end
```

---

## Implementation Approach

### 1. Configuration

```ruby
Langfuse.configure do |config|
  config.cache_backend = :rails
  config.cache_ttl = 300                      # Fresh for 5 minutes
  config.cache_stale_while_revalidate = true  # Enable SWR (opt-in)
  config.cache_stale_ttl = 300                # Serve stale for 5 more minutes
  config.cache_refresh_threads = 5            # Thread pool size (see analysis below)
end
```

**New config options:**
- `cache_stale_while_revalidate` (Boolean, default: false) - Enable SWR
- `cache_stale_ttl` (Integer, default: same as cache_ttl) - Grace period duration
- `cache_refresh_threads` (Integer, default: 5) - Background thread pool size

### 2. RailsCacheAdapter Enhancement

```ruby
require 'concurrent'

class RailsCacheAdapter
  def initialize(ttl:, stale_ttl: nil, refresh_threads: 5, ...)
    @ttl = ttl
    @stale_ttl = stale_ttl || ttl
    @thread_pool = Concurrent::CachedThreadPool.new(
      max_threads: refresh_threads,
      min_threads: 2,
      max_queue: 50,
      fallback_policy: :discard  # Drop oldest if queue full
    )
  end

  # New method for SWR
  def fetch_with_stale_while_revalidate(key, &block)
    entry = get_entry_with_metadata(key)

    if entry && entry[:fresh_until] > Time.now
      # FRESH - return immediately
      return entry[:data]
    elsif entry && entry[:stale_until] > Time.now
      # REVALIDATE - return stale + refresh in background
      schedule_refresh(key, &block)
      return entry[:data]  # Instant response! ✨
    else
      # STALE or MISS - must fetch synchronously
      fetch_and_cache_with_metadata(key, &block)
    end
  end

  private

  def schedule_refresh(key, &block)
    # Prevent duplicate refreshes
    refresh_lock_key = "#{namespaced_key(key)}:refreshing"
    return unless acquire_refresh_lock(refresh_lock_key)

    @thread_pool.post do
      begin
        value = block.call
        set_with_metadata(key, value)
      ensure
        release_lock(refresh_lock_key)
      end
    end
  end

  def get_entry_with_metadata(key)
    # Fetch from Redis including timestamps
    raw = Rails.cache.read("#{namespaced_key(key)}:metadata")
    return nil unless raw

    JSON.parse(raw, symbolize_names: true)
  end

  def set_with_metadata(key, value)
    now = Time.now
    entry = {
      data: value,
      fresh_until: now + @ttl,
      stale_until: now + @ttl + @stale_ttl
    }

    # Store both data and metadata
    Rails.cache.write(namespaced_key(key), value, expires_in: @ttl + @stale_ttl)
    Rails.cache.write("#{namespaced_key(key)}:metadata", entry.to_json, expires_in: @ttl + @stale_ttl)

    value
  end

  def acquire_refresh_lock(lock_key)
    # Short-lived lock (60s) to prevent duplicate background refreshes
    Rails.cache.write(lock_key, true, unless_exist: true, expires_in: 60)
  end
end
```

### 3. ApiClient Integration

```ruby
# In ApiClient#get_prompt
def get_prompt(name, version: nil, label: nil)
  raise ArgumentError, "Cannot specify both version and label" if version && label

  cache_key = PromptCache.build_key(name, version: version, label: label)

  # Use SWR if cache supports it and SWR is enabled
  if cache&.respond_to?(:fetch_with_stale_while_revalidate)
    cache.fetch_with_stale_while_revalidate(cache_key) do
      fetch_prompt_from_api(name, version: version, label: label)
    end
  elsif cache&.respond_to?(:fetch_with_lock)
    # Rails.cache with stampede protection (Phase 7.2)
    cache.fetch_with_lock(cache_key) do
      fetch_prompt_from_api(name, version: version, label: label)
    end
  elsif cache
    # In-memory cache - simple get/set
    cached_data = cache.get(cache_key)
    return cached_data if cached_data

    prompt_data = fetch_prompt_from_api(name, version: version, label: label)
    cache.set(cache_key, prompt_data)
    prompt_data
  else
    # No cache
    fetch_prompt_from_api(name, version: version, label: label)
  end
end
```

---

## Thread Pool Sizing Analysis

### Calculation

```
Threads = (Number of prompts × API latency) / Desired refresh time

Example (SimplePractice):
- Prompts: 50 unique prompts
- API latency: 200ms
- Desired refresh time: 5 seconds (before users notice stale data)

Threads = (50 × 0.2) / 5 = 2 threads minimum
Add 25% buffer: 2 × 1.25 = 2.5 → 3 threads

With 100 prompts:
Threads = (100 × 0.2) / 5 = 4 threads minimum
Add 25% buffer: 4 × 1.25 = 5 threads ✅
```

### Scenarios

**Scenario 1: Steady State (Distributed Expiry)**
```
TTL: 5 minutes = 300 seconds
Prompts: 50 total

Expiry rate: 50 prompts / 300 seconds = 0.16 prompts/second
           = ~1 prompt every 6 seconds

Thread requirement: 1 thread sufficient
```

**Scenario 2: Post-Deploy (Worst Case - All Expire Together)**
```
Prompts: 50 all cached at T=0
At T=5min: All 50 hit "revalidate" state simultaneously

With 2 threads:  50 ÷ 2 = 25 batches × 200ms = 5 seconds ⚠️
With 5 threads:  50 ÷ 5 = 10 batches × 200ms = 2 seconds ✅
With 10 threads: 50 ÷ 10 = 5 batches × 200ms = 1 second ✅
```

### Recommendations

**Option A: Fixed Pool (Simplest)**
```ruby
config.cache_refresh_threads = 5  # Default, configurable
@thread_pool = Concurrent::FixedThreadPool.new(5)
```
- **Pros**: Simple, predictable, easy to reason about
- **Cons**: May be too few (large apps) or too many (small apps)

**Option B: Auto-Sizing Pool (Recommended)**
```ruby
@thread_pool = Concurrent::CachedThreadPool.new(
  max_threads: 10,      # Cap at 10
  min_threads: 2,       # Keep 2 warm
  max_queue: 50,        # Queue up to 50 refreshes
  fallback_policy: :discard  # Drop oldest if queue full
)
```
- **Pros**: Self-adjusts to load, efficient resource usage
- **Cons**: Slightly more complex behavior

**Option C: Calculated Based on Config**
```ruby
def default_refresh_threads
  # Estimate: 1 thread per 25 prompts, min 2, max 10
  estimated_prompts = config.cache_estimated_prompts || 50
  threads = (estimated_prompts / 25.0).ceil
  [[threads, 2].max, 10].min
end
```
- **Pros**: Automatically sized based on expected load
- **Cons**: Requires estimating number of prompts

**Recommendation**: Use **Option B (Auto-Sizing Pool)** - best balance of simplicity and efficiency.

---

## Benefits

### 1. Better User Experience
- Users almost never wait for API calls
- Consistent low latency (~1ms cache reads)
- Only "too stale" requests pay the 100ms cost

### 2. Reduced Perceived Latency
```
Without SWR:
- 99% of requests: 1ms (cached)
- 1% of requests: 100ms (first after expiry)
- P99 latency: 100ms

With SWR:
- 99.9% of requests: 1ms (cached or stale)
- 0.1% of requests: 100ms (truly stale)
- P99 latency: 1ms ✨
```

### 3. Graceful Degradation
- If Langfuse API is slow/down, users still get stale data
- Only after grace period do requests fail
- Gives time to fix issues without user impact

### 4. Smoother Load Pattern
- Background refreshes happen asynchronously
- No thundering herd at expiry time
- API load is distributed over time

---

## Trade-offs

### Pros
✅ Near-instant response times (serve stale data)
✅ Background refresh doesn't block requests
✅ Dramatically reduces P99 latency
✅ More resilient to API slowdowns
✅ Smooth cache warming (no cold-start spikes)

### Cons
❌ Users might get slightly outdated data
❌ More complex caching logic
❌ Requires background thread pool (~10-20MB memory)
❌ Stale data could be incorrect if prompts change frequently
❌ Adds dependency on concurrent-ruby gem

---

## When to Use SWR

**Good for:**
- ✅ Prompts that don't change often (production prompts are typically stable)
- ✅ High-traffic applications where latency matters
- ✅ Systems where eventual consistency is acceptable
- ✅ Apps with many processes (background refresh amortized)

**Not ideal for:**
- ❌ Prompts that change frequently (users might see old versions)
- ❌ Critical data that must always be fresh
- ❌ Low-traffic apps (background refresh overhead not worth it)
- ❌ Apps sensitive to memory usage (thread pool overhead)

---

## Example: SimplePractice Impact

**Without SWR (current with Phase 7.2):**
```
- 1,200 processes
- 50 prompts
- Cache expires every 5 minutes
- First request after expiry: 100ms latency
- Other 1,199 requests: 1ms (stampede protection)
```

**With SWR:**
```
- ALL 1,200 requests: 1ms latency ✨
- Background refresh happens without blocking
- Stale data served for up to 5 more minutes if refresh fails
- Same 50 API calls every 5 minutes (no extra API load)
```

---

## Testing Strategy

### Unit Tests

1. **Cache state transitions**
   - Fresh → Revalidate → Stale
   - Timestamps correctly set

2. **Background refresh**
   - Scheduled correctly
   - Not duplicated (refresh lock)
   - Executes asynchronously

3. **Thread pool behavior**
   - Queues refreshes
   - Discards on overflow
   - Scales up/down

### Integration Tests

1. **With ApiClient**
   - Returns stale data immediately
   - Background refresh completes
   - Next request gets fresh data

2. **Concurrency**
   - Multiple processes hit revalidate state
   - Only one background refresh happens

3. **Error handling**
   - Background refresh fails → keep serving stale
   - Background refresh succeeds → cache updated

### Load Tests

1. **Post-deploy scenario**
   - All prompts expire simultaneously
   - Measure refresh time with different thread pool sizes

2. **Steady state**
   - Measure latency distribution (P50, P99, P999)
   - Verify background refreshes don't impact user requests

---

## Dependencies

**New Gem:**
- `concurrent-ruby ~> 1.2` - Thread pool management

**Existing:**
- Rails.cache (Redis) - Already required for Phase 7.1

---

## Estimated Effort

**Lines of Code:** ~200-250 new lines
- RailsCacheAdapter: ~100 lines (fetch_with_stale_while_revalidate, metadata methods)
- Config: ~20 lines (new options, validation)
- ApiClient: ~20 lines (integration)
- Tests: ~60-100 lines

**Complexity:** Medium
- Thread pool management (concurrent-ruby handles this)
- Metadata storage in Redis (straightforward)
- Background refresh scheduling (lock-based deduplication)

**Testing Effort:** Medium-High
- Background/async behavior harder to test
- Need timing-based tests (sleep, wait for refresh)
- Concurrency edge cases

**Time Estimate:** 4-6 hours
- 2 hours: Implementation
- 2 hours: Testing
- 1 hour: Documentation
- 1 hour: Buffer/debugging

---

## Future Enhancements

### Phase 7.3.1: Smart Refresh Scheduling
Instead of refreshing immediately on first stale request, schedule refreshes intelligently:
- Predict when prompts will expire based on usage patterns
- Pre-refresh popular prompts before they go stale
- Distribute refreshes to avoid spikes

### Phase 7.3.2: Adaptive TTL
Automatically adjust TTL based on prompt change frequency:
- Track how often prompts change in Langfuse
- Increase TTL for stable prompts
- Decrease TTL for frequently updated prompts

### Phase 7.3.3: Metrics & Observability
Add instrumentation for:
- Stale hit rate
- Background refresh success rate
- Time spent in each cache state
- Thread pool utilization

---

## Decision: Not Implementing (Yet)

**Rationale:**
- Phase 7.1 (Rails.cache adapter) + Phase 7.2 (stampede protection) already provide excellent performance
- Stampede protection ensures only 1 API call per cache miss (not 1,200)
- The 100ms latency hit happens very infrequently (once per TTL window)
- Added complexity (thread pool, metadata, concurrent-ruby dependency) may not be worth the marginal latency improvement
- Can revisit if P99 latency becomes a problem in production

**When to Reconsider:**
- Users complain about latency spikes
- P99 latency metrics show cache expiry causing issues
- Langfuse API becomes slower (>500ms)
- Need to support very high traffic (10,000+ requests/sec)

---

## References

- **HTTP Stale-While-Revalidate**: [RFC 5861](https://datatracker.ietf.org/doc/html/rfc5861)
- **SWR Pattern**: [Vercel SWR Library](https://swr.vercel.app/)
- **concurrent-ruby**: [GitHub](https://github.com/ruby-concurrency/concurrent-ruby)
- **Thread Pool Sizing**: [Little's Law](https://en.wikipedia.org/wiki/Little%27s_law)
