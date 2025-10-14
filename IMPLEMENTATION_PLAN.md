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
*Goal: Fast repeated access to prompts*

### 4.1 Simple In-Memory Cache ⬜
Build: `Langfuse::PromptCache` (simple version)
- [ ] Create cache with hash storage
- [ ] Implement CacheItem class (value, expiry)
- [ ] Add set(key, value, ttl)
- [ ] Add get_including_expired(key)
- [ ] Add create_key(name:, version:, label:)
- [ ] Thread safety with Mutex
- [ ] Write tests

**Files to create:**
- `lib/langfuse/prompt_cache.rb`
- `spec/langfuse/prompt_cache_spec.rb`

**Skip for now:**
- LRU eviction
- Background refresh
- Stampede protection
We'll add these later when needed!

### 4.2 Integrate Cache with Client ⬜
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

**Skip for now:** Stale-while-revalidate - we'll add later

**Milestone:** Basic caching works!

---

## PHASE 5: Global Configuration (Week 2, Day 2)
*Goal: Rails-friendly initialization*

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

### 5.2 Client Initialization Flexibility ⬜
Extend: `Langfuse::Client`
- [ ] Support Config object in initialize
- [ ] Support hash options in initialize
- [ ] Support global config fallback
- [ ] Write tests for all three patterns

**Milestone:** Can use global config pattern like LaunchDarkly!

---

## PHASE 6: Convenience and Resilience (Week 2, Day 3)
*Goal: Production-ready error handling*

### 6.1 Fallback Support ⬜
Extend: `Langfuse::Client#get_prompt`
- [ ] Add fallback option
- [ ] Add type option (required with fallback)
- [ ] Validate fallback type matches
- [ ] Return fallback on API errors
- [ ] Log errors when falling back
- [ ] Write tests

### 6.2 Compile Prompt Convenience Method ⬜
Extend: `Langfuse::Client`
- [ ] Implement compile_prompt(name, variables:, placeholders:, **options)
- [ ] One-step get + compile
- [ ] Support fallback option
- [ ] Write tests

### 6.3 Retry Logic ⬜
Extend: `Langfuse::ApiClient`
- [ ] Add faraday-retry dependency
- [ ] Configure retry middleware
- [ ] Test retry behavior (with WebMock failure simulation)

**Dependencies added:** `faraday-retry ~> 2.0`

**Milestone:** Basic Phase 1 MVP complete! 🎉

---

## PHASE 7: Advanced Caching (Week 3, Day 1)
*Goal: Production-grade caching*

### 7.1 LRU Eviction ⬜
Extend: `Langfuse::PromptCache`
- [ ] Add max_size configuration
- [ ] Track access order
- [ ] Implement LRU eviction
- [ ] Write tests

### 7.2 Stale-While-Revalidate ⬜
Extend: `Langfuse::PromptCache` and `Client`
- [ ] Detect expired cache
- [ ] Return stale value immediately
- [ ] Trigger background refresh
- [ ] Add concurrent-ruby dependency for thread pool
- [ ] Write tests

**Dependencies added:** `concurrent-ruby ~> 1.2`

### 7.3 Stampede Protection ⬜
Extend: `Langfuse::PromptCache`
- [ ] Track refreshing keys
- [ ] Prevent duplicate refreshes
- [ ] Write concurrency tests

**Milestone:** Production-grade caching!

---

## PHASE 8: CRUD Operations (Week 3, Days 2-3)
*Goal: Create and update prompts*

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
- [ ] Cache invalidation on successful update
- [ ] Write tests

### 8.3 Invalidate Cache ⬜
Extend: `Langfuse::Client`
- [ ] Implement invalidate_cache(name)
- [ ] Write tests

### 8.4 Chat Placeholders (Full) ⬜
Extend: `Langfuse::ChatPromptClient`
- [ ] Implement full placeholder resolution in compile
- [ ] Handle empty arrays
- [ ] Validate placeholder structure
- [ ] Support required_placeholders parameter
- [ ] Write comprehensive tests

**Milestone:** Full CRUD operations!

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
- [ ] Add ActiveSupport::Notifications instrumentation
- [ ] Document metric emission
- [ ] Example StatsD/Datadog integration
- [ ] Write example monitoring code

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
- None yet

### Technical Debt
*(Track shortcuts taken that need revisiting)*
- None yet

### Decisions Made
*(Document key technical decisions)*
- None yet
