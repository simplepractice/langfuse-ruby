# Langfuse Ruby - Prompt Management Implementation Plan

## Overview
This document tracks our iterative development of prompt management functionality for the langfuse-ruby gem, inspired by LaunchDarkly's excellent API design.

## Design Principles
- **Iterative Development**: Build small, testable increments
- **Minimal Dependencies**: Add dependencies only when needed
- **LaunchDarkly Patterns**: Follow proven patterns from LaunchDarkly gem
- **Test-Driven**: Each increment should be fully tested before moving forward

---

## PHASE 0: Foundation (Start Here)
*Goal: Set up project structure and basic scaffolding*

### 0.1 Project Setup ⬜
- [ ] Create gemspec file with basic metadata
- [ ] Set up lib/ directory structure
- [ ] Create basic Gemfile with minimal dependencies
- [ ] Set up RSpec for testing
- [ ] Create .gitignore
- [ ] Add README.md with project vision

**Dependencies at this stage:**
- Development: `rspec`, `simplecov`
- None for runtime yet

**Questions to answer:**
- What Ruby versions do we support? (Design doc says >= 2.7)
- Do we want Rubocop from the start?

---

## PHASE 1: Minimal HTTP Client (Week 1, Days 1-2)
*Goal: Ability to fetch a prompt from Langfuse API*

### 1.1 Configuration Object ⬜
Build: `Langfuse::Config`
- [ ] Create Config class with basic attributes (public_key, secret_key, base_url)
- [ ] Add validate! method
- [ ] Write tests for Config
- [ ] Default values for base_url

**Files to create:**
- `lib/langfuse/config.rb`
- `spec/langfuse/config_spec.rb`

### 1.2 API Client Foundation ⬜
Build: `Langfuse::ApiClient` (minimal version)
- [ ] Add Faraday dependency
- [ ] Create ApiClient class with initialization
- [ ] Implement Basic Auth helper
- [ ] Write connection builder
- [ ] Test authentication header generation

**Dependencies added:** `faraday ~> 2.0`

**Files to create:**
- `lib/langfuse/api_client.rb`
- `spec/langfuse/api_client_spec.rb`

### 1.3 GET Prompt Endpoint ⬜
Extend: `Langfuse::ApiClient`
- [ ] Implement get_prompt(name, version:, label:)
- [ ] Add error classes (ApiError, NotFoundError, UnauthorizedError)
- [ ] Handle response parsing (symbolize keys)
- [ ] Add tests with WebMock for HTTP stubbing

**Dependencies added:** `webmock ~> 3.18` (dev)

**Files to create:**
- `lib/langfuse/errors.rb`
- `spec/langfuse/api_client_get_prompt_spec.rb`

**Test with:** Real API call (manually) to verify integration

---

## PHASE 2: Simple Prompt Client (Week 1, Days 2-3)
*Goal: Return a usable prompt object*

### 2.1 TextPromptClient (No Compilation) ⬜
Build: `Langfuse::TextPromptClient`
- [ ] Create class with attr_readers (name, version, prompt, config, labels, tags)
- [ ] Initialize from API response hash
- [ ] Add to_json method
- [ ] Write tests

**Files to create:**
- `lib/langfuse/text_prompt_client.rb`
- `spec/langfuse/text_prompt_client_spec.rb`

**Skip for now:** compile() and to_langchain() methods - we'll add these later

### 2.2 ChatPromptClient (No Compilation) ⬜
Build: `Langfuse::ChatPromptClient`
- [ ] Create class similar to TextPromptClient
- [ ] Handle array-based prompt structure
- [ ] Add message normalization
- [ ] Write tests

**Files to create:**
- `lib/langfuse/chat_prompt_client.rb`
- `spec/langfuse/chat_prompt_client_spec.rb`

### 2.3 Simple Client Integration ⬜
Build: `Langfuse::Client` (minimal version)
- [ ] Create Client class with config
- [ ] Initialize ApiClient
- [ ] Implement get_prompt(name, **options) - no caching yet!
- [ ] Build correct prompt client based on type
- [ ] Write integration tests

**Files to create:**
- `lib/langfuse/client.rb`
- `spec/langfuse/client_spec.rb`

**Milestone:** Can fetch and return prompt objects!

---

## PHASE 3: Add Variable Substitution (Week 1, Day 4)
*Goal: Make prompts actually useful with compile()*

### 3.1 Mustache Integration ⬜
- [ ] Add mustache dependency
- [ ] Test mustache behavior with Ruby hash symbol/string keys

**Dependencies added:** `mustache ~> 1.1`

### 3.2 TextPromptClient#compile ⬜
Extend: `Langfuse::TextPromptClient`
- [ ] Implement compile(variables = {})
- [ ] Handle symbol and string keys
- [ ] Handle missing variables gracefully
- [ ] Write comprehensive tests

**Test cases:**
- All variables provided
- Some variables missing
- Extra variables provided
- Symbol vs string keys
- Nil values

### 3.3 ChatPromptClient#compile (Basic) ⬜
Extend: `Langfuse::ChatPromptClient`
- [ ] Implement compile(variables = {}, placeholders = {})
- [ ] Variable substitution in message content
- [ ] Skip placeholder handling for now (keep them in output)
- [ ] Write tests

**Note:** Full placeholder resolution comes in Phase 2 of the design doc

**Milestone:** Can fetch and compile prompts with variables!

---

## PHASE 4: Add Caching (Week 2, Days 1-2)
*Goal: Fast repeated access to prompts with distributed caching*

**Important:** This phase uses Rails.cache (Redis) from the start for production scale (1,200+ processes).

### 4.1 Rails.cache Backend ⬜
Build: `Langfuse::PromptCache` (Rails.cache version)
- [ ] Create cache wrapper around Rails.cache
- [ ] Implement CacheItem class (value, expiry)
- [ ] Add set(key, value, ttl) using Rails.cache.write
- [ ] Add get_including_expired(key) using Rails.cache.read
- [ ] Add create_key(name:, version:, label:)
- [ ] Write tests

**Files to create:**
- `lib/langfuse/prompt_cache.rb`
- `spec/langfuse/prompt_cache_spec.rb`

**Key differences from design doc:**
- Skip in-memory cache entirely (not suitable for multi-process deployment)
- Use Rails.cache (Redis) for shared state across processes
- No LRU eviction needed (Redis handles this)
- No Mutex needed (Redis is thread-safe)

### 4.2 Distributed Stampede Protection ⬜
Extend: `Langfuse::PromptCache`
- [ ] Implement fetch_with_stampede_protection method
- [ ] Use Redis lock (Rails.cache.write with unless_exist: true)
- [ ] Handle lock acquisition failure gracefully
- [ ] Add timeout for lock (10 seconds)
- [ ] Write concurrency tests

**Implementation pattern:**
```ruby
def fetch_with_stampede_protection(key, ttl:, &block)
  # Try cache first
  cached = Rails.cache.read(key)
  return cached if cached && !expired?(cached)

  # Acquire refresh lock
  lock_key = "#{key}:refresh_lock"
  acquired = Rails.cache.write(lock_key, true, unless_exist: true, expires_in: 10)

  if acquired
    value = block.call
    Rails.cache.write(key, value, expires_in: ttl)
    value
  else
    # Another process is refreshing - wait briefly and retry
    sleep(0.1)
    Rails.cache.read(key) || block.call
  end
end
```

### 4.3 Integrate Cache with Client ⬜
Extend: `Langfuse::Client`
- [ ] Add cache instance to Client
- [ ] Implement cache-first logic in get_prompt
- [ ] Handle cache miss -> API fetch -> store
- [ ] Handle cache hit (fresh only for now)
- [ ] Add cache_ttl option
- [ ] Write tests

**Test cases:**
- Cache miss
- Cache hit (fresh)
- Cache disabled (ttl = 0)
- Concurrent requests (stampede protection)

**Skip for now:** Stale-while-revalidate - keeping it simple

**Milestone:** Distributed caching with stampede protection!

---

## PHASE 5: Global Configuration (Week 2, Day 2)
*Goal: Rails-friendly initialization with production resilience settings*

### 5.1 Global Langfuse Module ⬜
Build: `Langfuse` module methods
- [ ] Add Langfuse.configure block
- [ ] Add Langfuse.configuration getter
- [ ] Add Langfuse.client singleton
- [ ] Add Langfuse.reset! for testing
- [ ] Write tests

**Files to modify:**
- `lib/langfuse.rb` (main entry point)

**Test with:** Example Rails initializer pattern

### 5.2 Config Options for Scale ⬜
Extend: `Langfuse::Config`
- [ ] Add require_fallback attribute (default: false)
- [ ] Add enable_instrumentation attribute (default: true)
- [ ] Add cache_backend attribute (for future: :memory vs :rails)
- [ ] Update validate! to check for Rails.cache when using :rails backend
- [ ] Write tests

**New config options:**
```ruby
config.require_fallback = Rails.env.production?  # Enforce fallbacks
config.enable_instrumentation = ENV.fetch('LANGFUSE_METRICS', 'true') == 'true'
config.cache_backend = :rails  # Use Rails.cache (Redis)
```

### 5.3 Client Initialization Flexibility ⬜
Extend: `Langfuse::Client`
- [ ] Support Config object in initialize
- [ ] Support hash options in initialize
- [ ] Support global config fallback
- [ ] Write tests for all three patterns

**Milestone:** Can use global config pattern with production-ready settings!

---

## PHASE 6: Convenience and Resilience (Week 2, Day 3)
*Goal: Production-ready error handling with enforced resilience*

### 6.1 Fallback Support ⬜
Extend: `Langfuse::Client#get_prompt`
- [ ] Add fallback option
- [ ] Add type option (required with fallback)
- [ ] Validate fallback type matches
- [ ] Return fallback on API errors
- [ ] Log errors when falling back
- [ ] Write tests

### 6.2 Fallback Enforcement ⬜
Extend: `Langfuse::Client#get_prompt`
- [ ] Check config.require_fallback setting
- [ ] Raise ConfigurationError if fallback not provided when required
- [ ] Add clear error message with usage example
- [ ] Write tests for enforcement

**Implementation:**
```ruby
def get_prompt(name, **options)
  if @config.require_fallback && !options[:fallback]
    raise ConfigurationError,
      "Fallback is required (require_fallback: true). " \
      "Provide fallback: option to ensure resilience."
  end
  # ... rest of implementation
end
```

### 6.3 Instrumentation with Config Toggle ⬜
Extend: `Langfuse::Client`
- [ ] Add instrument private method
- [ ] Check config.enable_instrumentation before emitting
- [ ] Emit events for get_prompt (duration, cache hit, fallback used)
- [ ] Write tests

**Implementation:**
```ruby
def instrument(event, payload)
  return unless @config.enable_instrumentation
  return unless defined?(ActiveSupport::Notifications)
  ActiveSupport::Notifications.instrument("langfuse.#{event}", payload)
end
```

### 6.4 Compile Prompt Convenience Method ⬜
Extend: `Langfuse::Client`
- [ ] Implement compile_prompt(name, variables:, placeholders:, **options)
- [ ] One-step get + compile
- [ ] Support fallback option
- [ ] Write tests

### 6.5 Retry Logic ⬜
Extend: `Langfuse::ApiClient`
- [ ] Add faraday-retry dependency
- [ ] Configure retry middleware (basic: max 2, interval 0.5)
- [ ] Test retry behavior (with WebMock failure simulation)

**Dependencies added:** `faraday-retry ~> 2.0`

**Note:** Advanced retry tuning comes in Phase 7

**Milestone:** Basic Phase 1 MVP complete with enforced resilience! 🎉

---

## PHASE 7: Circuit Breaker and Retry Tuning (Week 3, Day 1)
*Goal: Prevent cascading failures and optimize retry behavior*

### 7.1 Circuit Breaker Integration ⬜
Add: Circuit breaker to `Langfuse::ApiClient`
- [ ] Add stoplight gem dependency
- [ ] Initialize Stoplight circuit breaker in ApiClient
- [ ] Configure thresholds (5 failures, 30s timeout)
- [ ] Configure Redis data store for shared state
- [ ] Wrap API calls with circuit breaker
- [ ] Handle RedLight errors gracefully (return nil)
- [ ] Write tests

**Dependencies added:** `stoplight ~> 4.0`

**Implementation:**
```ruby
@circuit_breaker = Stoplight("langfuse-api")
  .with_threshold(5)
  .with_timeout(30)
  .with_cool_off_time(10)
  .with_data_store(Stoplight::DataStore::Redis.new(Redis.current))

def get_prompt(name, **options)
  @circuit_breaker.run do
    connection.get("/api/public/v2/prompts/#{name}")
  end
rescue Stoplight::Error::RedLight => e
  logger.warn("Langfuse circuit breaker open: #{e.message}")
  nil  # Caller handles with fallback
end
```

### 7.2 Advanced Retry Configuration ⬜
Extend: `Langfuse::ApiClient` retry middleware
- [ ] Reduce max retries from 2 to 1 (total attempts: 2 instead of 3)
- [ ] Increase jitter (interval_randomness: 0.75)
- [ ] Only retry safe methods (GET only)
- [ ] Only retry specific statuses (429, 503, 504)
- [ ] Test improved retry behavior

**Updated retry config:**
```ruby
conn.request :retry,
  max: 1,                        # Reduced from 2
  interval: 0.5,
  interval_randomness: 0.75,     # Increased from 0.5
  backoff_factor: 2,
  methods: [:get],               # Only GET
  retry_statuses: [429, 503, 504],  # Removed 500, 502
  exceptions: [
    Faraday::TimeoutError,
    Faraday::ConnectionFailed
  ]
```

### 7.3 Circuit Breaker Metrics ⬜
Extend: Instrumentation
- [ ] Add circuit breaker state to instrumentation payload
- [ ] Emit circuit open/close events
- [ ] Document monitoring setup for circuit breaker
- [ ] Write example Datadog/StatsD integration

**Milestone:** Production-grade reliability with circuit breaker!

---

## PHASE 8: CRUD Operations and Cache Warming (Week 3, Days 2-3)
*Goal: Create and update prompts, plus deployment tooling*

### 8.1 Create Prompt ⬜
Extend: `Langfuse::ApiClient` and `Client`
- [ ] Implement ApiClient#create_prompt
- [ ] Implement Client#create_prompt with validation
- [ ] Write tests with VCR

**Dependencies added:** `vcr ~> 6.1` (dev)

### 8.2 Update Prompt ⬜
Extend: `Langfuse::ApiClient` and `Client`
- [ ] Implement ApiClient#update_prompt_version
- [ ] Implement Client#update_prompt
- [ ] Cache invalidation on successful update (Redis)
- [ ] Write tests

### 8.3 Invalidate Cache ⬜
Extend: `Langfuse::Client`
- [ ] Implement invalidate_cache(name)
- [ ] Clear all cache keys matching prompt name pattern
- [ ] Write tests

### 8.4 Cache Warming Rake Task ⬜
Add: Deployment tooling for cache warming
- [ ] Create lib/tasks/langfuse.rake
- [ ] Implement warm_cache task with prompt list argument
- [ ] Support ENV variable for prompt list
- [ ] Add success/failure reporting
- [ ] Document usage in README

**Files to create:**
- `lib/tasks/langfuse.rake`

**Implementation:**
```ruby
namespace :langfuse do
  desc "Warm prompt cache with specified prompts"
  task :warm_cache, [:prompts] => :environment do |t, args|
    prompts = if args[:prompts]
                args[:prompts].split(',')
              else
                ENV.fetch('LANGFUSE_PROMPTS_TO_WARM', '').split(',')
              end

    client = Langfuse.client
    results = { success: [], failed: [] }

    prompts.each do |name|
      begin
        client.get_prompt(name.strip, cache_ttl: 300)
        results[:success] << name
      rescue => e
        results[:failed] << name
      end
    end

    puts "Success: #{results[:success].size}/#{prompts.size}"
  end
end
```

**Usage:**
```bash
# In deploy script
bundle exec rake langfuse:warm_cache['greeting,conversation,rag-pipeline']

# Or via environment variable
LANGFUSE_PROMPTS_TO_WARM=greeting,conversation rake langfuse:warm_cache
```

### 8.5 Chat Placeholders (Full) ⬜
Extend: `Langfuse::ChatPromptClient`
- [ ] Implement full placeholder resolution in compile
- [ ] Handle empty arrays
- [ ] Validate placeholder structure
- [ ] Support required_placeholders parameter
- [ ] Write comprehensive tests

**Milestone:** Full CRUD operations with deployment tooling!

---

## PHASE 9: LangChain Integration (Week 3, Day 4)
*Goal: LangChain compatibility*

### 9.1 Variable Transformation ⬜
Extend both prompt clients
- [ ] Implement transform_to_langchain_variables helper
- [ ] TextPromptClient#to_langchain
- [ ] ChatPromptClient#to_langchain (basic)
- [ ] Write tests

### 9.2 Placeholder Transformation ⬜
Extend: `ChatPromptClient#to_langchain`
- [ ] Handle resolved placeholders
- [ ] Handle unresolved placeholders
- [ ] Write tests

**Milestone:** LangChain integration complete!

---

## PHASE 10: Polish (Week 4)
*Goal: Production ready*

### 10.1 Observability ⬜
- [ ] Document ActiveSupport::Notifications integration (already implemented in Phase 6)
- [ ] Document enable_instrumentation config toggle
- [ ] Write comprehensive StatsD/Datadog integration examples
- [ ] Document circuit breaker monitoring
- [ ] Write example monitoring dashboards

### 10.2 Documentation ⬜
- [ ] Complete API documentation with YARD
- [ ] Write comprehensive README
- [ ] Add usage examples
- [ ] Write Rails integration guide
- [ ] Migration guide from hardcoded prompts

### 10.3 Code Quality ⬜
- [ ] Add Rubocop if not already present
- [ ] Fix all linter issues
- [ ] Verify test coverage >90%
- [ ] Add performance benchmarks

**Milestone:** 1.0 Release Ready! 🚀

---

## Questions to Answer Before Starting

### Implementation Questions
1. **Ruby version support**: Stick with >= 2.7 as per design doc?
2. **Existing gem**: Should we check if there's an existing langfuse-ruby gem to build on, or truly starting fresh?
3. **API credentials**: Do you have Langfuse API credentials for testing?

### API Design Questions (based on design doc)
1. **Flattened API**: Confirm we want `client.get_prompt()` not `client.prompt.get()`?
2. **Global config**: Confirm we want `Langfuse.configure` pattern?
3. **Method naming**: Ruby convention is snake_case - confirm `get_prompt` not `getPrompt`?

### Testing Questions
1. **VCR cassettes**: Should we commit VCR cassettes or gitignore them?
2. **Real API tests**: Should we have integration tests that hit real API (opt-in)?
3. **Coverage target**: 90% as per design doc?

---

## Current Status

**Phase:** Not started
**Last Updated:** 2025-10-13
**Current Increment:** 0.1 - Project Setup

---

## Notes

### LaunchDarkly Patterns to Follow
- Global configuration with `configure` block
- Singleton client with `Langfuse.client`
- Keyword arguments for all options
- Required fallback/defaults for resilience
- Flat API surface (methods on Client, not nested)
- Detail variants for debugging (`get_prompt_detail`)

### Deviations from Design Doc
*(Document any intentional changes from the design doc here)*

1. **Phase 4 - Redis Cache from Start**: Skipped in-memory cache implementation entirely. Design doc had incremental approach (simple in-memory → advanced in-memory → Rails.cache option), but production scale requirements (1,200 Passenger processes × 7 threads) demand shared cache from Day 1.

2. **Phase 4 - Distributed Stampede Protection**: Moved from Phase 7 to Phase 4. At scale, cache misses across 1,200 processes = 1,200 simultaneous API calls without this. Critical for production deployment.

3. **Phase 5 - Additional Config Options**: Added `require_fallback` and `enable_instrumentation` config options not in original design. These support production resilience and observability requirements.

4. **Phase 7 - Circuit Breaker Instead of Cache Improvements**: Replaced LRU eviction and stale-while-revalidate with circuit breaker pattern. With Redis cache, LRU/stale-while-revalidate less critical. Circuit breaker prevents cascading failures during Langfuse API outages.

5. **Phase 7 - Retry Tuning**: Reduced max retries from 2 to 1 (3 total attempts → 2). At scale, retry amplification during outages causes problems (1,200 processes × 50 prompts × 3 attempts = massive API load).

6. **Phase 8 - Cache Warming Rake Task**: Added deployment tooling not in original design. Helps prevent cold-start API spikes when all 1,200 processes restart simultaneously.

### Technical Debt
*(Track shortcuts taken that need revisiting)*
- None yet

### Decisions Made
*(Document key technical decisions)*

**2025-10-13 - Scale-Driven Architecture Changes**
- **Context**: Deploying to large Rails monolith (100 web services, 12 Passenger instances each, 7 threads per instance = 8,400 concurrent threads)
- **Key Problems Identified**:
  1. In-memory cache = 1,200 isolated caches with inconsistent invalidation
  2. Cache expiry without stampede protection = thundering herd (1,200 simultaneous API calls)
  3. Cold start (deploy/restart) = massive API spike
  4. Retry amplification during outages
  5. No circuit breaker = cascading failures

- **Solutions Implemented**:
  1. **Rails.cache (Redis) from Phase 4**: Shared cache across all processes
  2. **Distributed Stampede Protection**: Redis-based locks prevent duplicate refreshes
  3. **Circuit Breaker (Phase 7)**: Stoplight gem with Redis backend, shared state
  4. **Retry Tuning (Phase 7)**: Reduced retries, increased jitter, only retry safe methods
  5. **Fallback Enforcement (Phase 6)**: Config option to require fallbacks in production
  6. **Cache Warming Rake Task (Phase 8)**: Pre-populate cache before serving traffic
  7. **Instrumentation Config Toggle (Phase 5/6)**: Optional metrics emission

- **Trade-offs**:
  - ✅ Production-ready at scale from Day 1
  - ✅ No process isolation issues
  - ❌ Requires Redis (acceptable - already required for Rails.cache)
  - ❌ Slightly more complex initial implementation
  - ❌ Can't use gem without Redis (acceptable for target use case)

- **Alternative Considered**: Keep in-memory cache as default, add Rails.cache as opt-in
- **Why Rejected**: At target scale (1,200+ processes), in-memory cache is fundamentally broken. Better to build correctly from start than support two cache backends.

---

## PHASE 11: GitHub Actions CI/CD (Week 4+)
*Goal: Automated testing and quality checks on every push and pull request*

### 11.1 Basic CI Workflow ⬜
Build: `.github/workflows/ci.yml`
- [ ] Create .github/workflows directory
- [ ] Set up basic workflow structure
- [ ] Configure triggers (push to main, pull requests)
- [ ] Set up Ruby environment with ruby/setup-ruby action
- [ ] Configure bundler caching for faster builds
- [ ] Add checkout step

**Files to create:**
- `.github/workflows/ci.yml`

**Workflow triggers:**
```yaml
on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
```

### 11.2 RSpec Test Job ⬜
Extend: CI workflow
- [ ] Add job for running RSpec tests
- [ ] Run bundle install with caching
- [ ] Execute bundle exec rspec
- [ ] Generate test results
- [ ] Upload SimpleCov coverage artifacts
- [ ] Set up matrix strategy for multiple Ruby versions (3.2, 3.3)

**Ruby versions to test:**
- 3.2 (minimum supported - per .ruby-version)
- 3.3 (latest stable)

**Test job structure:**
```yaml
test:
  strategy:
    matrix:
      ruby: ['3.2', '3.3']
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: ruby/setup-ruby@v1
      with:
        ruby-version: ${{ matrix.ruby }}
        bundler-cache: true
    - run: bundle exec rspec
    - uses: actions/upload-artifact@v4
      if: matrix.ruby == '3.3'
      with:
        name: coverage
        path: coverage/
```

### 11.3 Rubocop Linting Job ⬜
Extend: CI workflow
- [ ] Add separate job for Rubocop linting
- [ ] Run bundle exec rubocop
- [ ] Fail build on linting errors
- [ ] Run only on Ruby 3.3 (no need for matrix)
- [ ] Use annotations for inline PR comments

**Linter job structure:**
```yaml
lint:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: ruby/setup-ruby@v1
      with:
        ruby-version: '3.3'
        bundler-cache: true
    - run: bundle exec rubocop
```

### 11.4 Coverage Reporting ⬜
Extend: CI workflow
- [ ] Add codecov/codecov-action or coverallsapp/github-action
- [ ] Upload coverage reports from test job
- [ ] Configure coverage thresholds (90% target)
- [ ] Generate coverage badge for README

**Coverage action (choose one):**
```yaml
# Option 1: Codecov
- uses: codecov/codecov-action@v3
  with:
    files: ./coverage/coverage.json
    flags: unittests
    fail_ci_if_error: true

# Option 2: Coveralls
- uses: coverallsapp/github-action@v2
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    path-to-lcov: ./coverage/lcov.info
```

### 11.5 Status Badges and README Updates ⬜
Update: README.md
- [ ] Add CI status badge
- [ ] Add coverage badge
- [ ] Add Ruby version badge
- [ ] Add gem version badge (when published)
- [ ] Document CI/CD process

**Badge examples:**
```markdown
[![CI](https://github.com/USERNAME/langfuse-ruby/workflows/CI/badge.svg)](https://github.com/USERNAME/langfuse-ruby/actions)
[![Coverage](https://codecov.io/gh/USERNAME/langfuse-ruby/branch/main/graph/badge.svg)](https://codecov.io/gh/USERNAME/langfuse-ruby)
[![Ruby Version](https://img.shields.io/badge/ruby-3.2%2B-ruby.svg)](https://www.ruby-lang.org)
```

### 11.6 Branch Protection Rules ⬜
Configure: GitHub repository settings
- [ ] Require status checks to pass before merging
- [ ] Require test job (both Ruby versions) to pass
- [ ] Require lint job to pass
- [ ] Require up-to-date branches before merging
- [ ] Require pull request reviews (optional)

**Protection rules:**
- Status checks required: `test (3.2)`, `test (3.3)`, `lint`
- Require branches to be up to date before merging
- Include administrators: Yes

### 11.7 Performance Optimization ⬜
Extend: CI workflow
- [ ] Add bundler cache key based on Gemfile.lock
- [ ] Enable parallel test execution (if multiple specs)
- [ ] Set up dependency caching
- [ ] Configure workflow concurrency for PR updates
- [ ] Optimize checkout depth (shallow clone)

**Concurrency configuration:**
```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

**Cache optimization:**
```yaml
- uses: ruby/setup-ruby@v1
  with:
    ruby-version: ${{ matrix.ruby }}
    bundler-cache: true # Automatically caches gems
```

### 11.8 Optional: Release Automation ⬜
Add: `.github/workflows/release.yml` (future phase)
- [ ] Create release workflow triggered by tags
- [ ] Build and publish gem to RubyGems.org
- [ ] Generate changelog from commits
- [ ] Create GitHub release with notes
- [ ] Upload gem artifact to release

**Note:** This is a future enhancement for when the gem is ready for public release (post Phase 10).

**Milestone:** Automated testing and quality checks on every commit! 🔄

---

## CI/CD Configuration Example

### Complete `.github/workflows/ci.yml` (Phase 11.1-11.4)
```yaml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    name: Test (Ruby ${{ matrix.ruby }})
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        ruby: ['3.2', '3.3']

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true

      - name: Run tests
        run: bundle exec rspec

      - name: Upload coverage (Ruby 3.3 only)
        if: matrix.ruby == '3.3'
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage/
          retention-days: 7

      - name: Upload coverage to Codecov
        if: matrix.ruby == '3.3'
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage/coverage.json
          flags: unittests
          fail_ci_if_error: false # Don't fail builds for coverage upload issues

  lint:
    name: Lint (Rubocop)
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.3'
          bundler-cache: true

      - name: Run Rubocop
        run: bundle exec rubocop --format github

  # All jobs must pass for PR merge
  ci-success:
    name: CI Success
    needs: [test, lint]
    runs-on: ubuntu-latest
    if: always()
    steps:
      - name: Check all jobs
        run: |
          if [ "${{ needs.test.result }}" != "success" ] || [ "${{ needs.lint.result }}" != "success" ]; then
            echo "One or more CI jobs failed"
            exit 1
          fi
```

### Benefits of This CI/CD Setup

1. **Multi-version Testing**: Ensures compatibility with Ruby 3.2+ as specified
2. **Fast Feedback**: Parallel test execution across Ruby versions
3. **Code Quality**: Automated linting prevents style issues
4. **Coverage Tracking**: Monitors test coverage over time
5. **Smart Caching**: Bundler cache speeds up builds (typical time: 30s → 10s)
6. **Concurrency Control**: Cancels outdated PR builds automatically
7. **Branch Protection**: Prevents merging broken code
8. **Annotations**: Rubocop errors show inline in PR reviews

### Estimated CI Run Time

- **Initial run** (no cache): ~2-3 minutes
- **Subsequent runs** (with cache): ~30-45 seconds
- **Parallel execution**: Test + Lint jobs run simultaneously

### Dependencies Required

**No new gem dependencies** - uses existing:
- `rspec` (already in Gemfile)
- `rubocop` (already in Gemfile)
- `simplecov` (already in Gemfile for coverage)

**GitHub Actions only** - free for public repositories
