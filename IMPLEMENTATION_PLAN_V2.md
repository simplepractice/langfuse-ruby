# Langfuse Ruby SDK - Implementation Roadmap

**Last Updated:** 2025-10-15
**Current Phase:** Phase 6 - Convenience Features

---

## Completed Phases ✅

### Phase 0: Foundation (COMPLETE)
- ✅ Project structure with gemspec
- ✅ RSpec with SimpleCov (99.6% coverage)
- ✅ Rubocop configuration
- ✅ Git repository setup

### Phase 1: HTTP Client (COMPLETE)
- ✅ Config class with validation
- ✅ ApiClient with Faraday + Basic Auth
- ✅ GET prompt endpoint
- ✅ Error classes (ApiError, NotFoundError, UnauthorizedError)
- ✅ 71 tests passing

### Phase 2: Prompt Clients (COMPLETE)
- ✅ TextPromptClient with metadata
- ✅ ChatPromptClient with message handling
- ✅ Client class with type detection
- ✅ 128 tests passing

### Phase 3: Variable Substitution (COMPLETE)
- ✅ Mustache integration
- ✅ TextPromptClient#compile with variables
- ✅ ChatPromptClient#compile with role-based messages
- ✅ Support for nested objects, lists, HTML escaping
- ✅ 128 tests passing

### Phase 4: In-Memory Caching (COMPLETE)
- ✅ PromptCache with TTL and LRU eviction
- ✅ Thread-safe with Monitor synchronization
- ✅ Cache key generation (name, version, label)
- ✅ Integrated into ApiClient
- ✅ 161 tests passing, 99.11% coverage

### Phase 5: Global Configuration (COMPLETE)
- ✅ Langfuse.configure block pattern
- ✅ Langfuse.client singleton
- ✅ Langfuse.reset! for testing
- ✅ Config validation on initialization
- ✅ 187 tests passing, 99.6% coverage

### Documentation (COMPLETE)
- ✅ Comprehensive README with examples
- ✅ API reference documentation
- ✅ Usage examples for text and chat prompts
- ✅ Configuration and caching guides

**Current Status:** Production-ready prompt management with in-memory caching!

---

## Next: Phase 6 - Convenience Features

*Goal: Make the SDK more ergonomic and production-friendly*

### 6.1 Compile Convenience Method
**Add to:** `Langfuse::Client`

```ruby
# One-liner: fetch + compile
text = client.compile_prompt("greeting", variables: { name: "Alice" })

# With fallback
text = client.compile_prompt(
  "greeting",
  variables: { name: "Alice" },
  fallback: "Hello {{name}}!",
  type: :text
)
```

**Tasks:**
- [ ] Implement `compile_prompt(name, variables: {}, **options)`
- [ ] Support fallback option
- [ ] Return compiled string for text prompts
- [ ] Return compiled messages array for chat prompts
- [ ] Write tests (happy path, fallback, errors)

### 6.2 Fallback Support
**Add to:** `Langfuse::Client#get_prompt`

```ruby
# Graceful degradation on API errors
prompt = client.get_prompt(
  "greeting",
  fallback: "Hello {{name}}!",
  type: :text  # Required with fallback
)
```

**Tasks:**
- [ ] Add `fallback:` and `type:` parameters to get_prompt
- [ ] Validate fallback type matches (text vs chat)
- [ ] Return fallback prompt client on API errors
- [ ] Log warnings when falling back
- [ ] Write tests (404, 401, 500, network errors)

### 6.3 Basic Retry Logic
**Add to:** `Langfuse::ApiClient`

Add automatic retries for transient errors:
- Max 2 retries (3 total attempts)
- Exponential backoff with jitter
- Only retry GET requests
- Only retry safe status codes (429, 503, 504)

**Tasks:**
- [ ] Add `faraday-retry` dependency
- [ ] Configure retry middleware in ApiClient
- [ ] Write tests with WebMock (simulate failures)
- [ ] Update README with retry behavior

**Dependencies:** `faraday-retry ~> 2.0`

### 6.4 Instrumentation Hooks (Optional)
**Add to:** `Langfuse::Client`

Emit events for observability (optional, ActiveSupport::Notifications):

```ruby
ActiveSupport::Notifications.subscribe("langfuse.get_prompt") do |event|
  # event.payload includes: name, duration, cache_hit, fallback_used
end
```

**Tasks:**
- [ ] Add private `instrument(event, payload)` method
- [ ] Check if ActiveSupport::Notifications is defined
- [ ] Emit events for get_prompt (duration, cache_hit, fallback_used)
- [ ] Document in README
- [ ] Write tests (with and without ActiveSupport)

**Milestone:** Ergonomic API with graceful degradation! 🎯

---

## Future Phases (Post-Launch)

### Phase 7: Advanced Caching (Optional)
*For users who need Redis/distributed caching*

- Background cache refresh (stale-while-revalidate)
- Rails.cache adapter (Redis backend)
- Distributed stampede protection
- Cache warming utilities

**Note:** In-memory cache works great for most apps. This is for high-scale deployments.

### Phase 8: CRUD Operations
*Goal: Create and update prompts via API*

- `create_prompt(name, prompt, type:, **options)`
- `update_prompt(name, prompt, **options)`
- Cache invalidation on updates
- VCR for testing

### Phase 9: LangChain Integration
*Goal: Export prompts to LangChain format*

- `TextPromptClient#to_langchain`
- `ChatPromptClient#to_langchain`
- Handle variable transformation
- Write integration examples

### Phase 10: Polish & 1.0 Release
*Goal: Production-ready 1.0*

- Complete YARD documentation
- Performance benchmarks
- Rails integration guide
- Migration guide from hardcoded prompts
- Gem publication to RubyGems

### Phase 11: CI/CD
*Goal: Automated testing and releases*

- GitHub Actions workflow
- Multi-version Ruby testing (3.2, 3.3)
- Rubocop linting
- Coverage reporting
- Automated gem releases

---

## Design Decisions

### Why In-Memory Cache First?
**Decision:** Built simple, thread-safe in-memory cache instead of Redis

**Reasoning:**
- ✅ Zero external dependencies (works everywhere)
- ✅ Fast and simple for most use cases
- ✅ Perfect for single-process apps, scripts, Sidekiq workers
- ✅ Easy to test and debug
- 🔄 Can add Redis as optional backend later (Phase 7)

**Trade-offs:**
- Each process has its own cache (not shared)
- Cache cleared on restart
- Not ideal for 1000+ process deployments

**For large deployments:** Phase 7 will add Redis support as an optional backend.

### Architecture Patterns
**Following LaunchDarkly:**
- Flat API (all methods on Client)
- Global configuration with `Langfuse.configure`
- Singleton pattern with `Langfuse.client`
- Keyword arguments everywhere
- Minimal dependencies (add only what's needed)

---

## Current Dependencies

**Runtime:**
- `faraday ~> 2.0` - HTTP client
- `mustache ~> 1.1` - Variable substitution

**Development:**
- `rspec` - Testing
- `rubocop` + `rubocop-rspec` - Linting
- `simplecov` - Coverage
- `webmock` - HTTP stubbing

**To Add in Phase 6:**
- `faraday-retry ~> 2.0` - Automatic retries

---

## Test Coverage Target

- **Current:** 99.6% (247/248 lines)
- **Target:** > 95% for 1.0 release
- **Status:** ✅ Exceeding target!

---

## Questions?

Check:
- **PROGRESS.md** - Detailed completion status
- **README.md** - Usage examples and API reference
- **langfuse-ruby-prompt-management-design.md** - Original design document
