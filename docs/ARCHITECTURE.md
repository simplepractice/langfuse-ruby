# Architecture Overview

High-level architecture and key design decisions for the Langfuse Ruby SDK.

## Table of Contents

- [Design Philosophy](#design-philosophy)
- [Core Components](#core-components)
- [Key Design Decisions](#key-design-decisions)
- [Data Flow](#data-flow)
- [Technology Choices](#technology-choices)

## Design Philosophy

The Langfuse Ruby SDK follows these core principles:

### 1. LaunchDarkly-Inspired API

**Flat API surface** - All methods on `Client`, not nested managers:

```ruby
# ✅ Good - Flat API
client.get_prompt("name")
client.compile_prompt("name", variables: {})

# ❌ Avoid - Nested managers
client.prompts.get("name")
client.prompts.compile("name")
```

**Why?** Simpler, more discoverable API with better IDE autocomplete support.

### 2. Rails-Friendly

Global configuration pattern that feels natural in Rails:

```ruby
# config/initializers/langfuse.rb
Langfuse.configure do |config|
  config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
  config.secret_key = ENV['LANGFUSE_SECRET_KEY']
end

# Use anywhere
client = Langfuse.client
```

### 3. Ruby Conventions

- **snake_case** for methods: `get_prompt`, not `getPrompt`
- **Symbol keys** in hashes: `{ role: :user }`
- **Keyword arguments**: `get_prompt(name, version: 2)`
- **Blocks** for configuration and scoping

### 4. Minimal Dependencies

Only add dependencies when absolutely necessary:

- **Faraday** - HTTP client (industry standard)
- **Mustache** - Variable templating (logic-less, secure)
- **OpenTelemetry** - Distributed tracing (CNCF standard)

No Rails dependency - works in any Ruby project.

### 5. Thread-Safe by Default

All components use proper synchronization:

- `PromptCache` uses Monitor
- `RailsCacheAdapter` uses Redis atomic operations
- OpenTelemetry handles context propagation

## Core Components

### 1. Configuration (`Langfuse::Config`)

Central configuration object with validation:

```ruby
config = Langfuse::Config.new do |c|
  c.public_key = "pk_..."
  c.secret_key = "sk_..."
  c.cache_ttl = 60
end
```

**Responsibilities:**
- Store SDK configuration
- Validate required settings
- Provide defaults

### 2. HTTP Client (`Langfuse::ApiClient`)

HTTP layer with Faraday:

```ruby
api_client = Langfuse::ApiClient.new(config, cache)
prompt_data = api_client.get_prompt("name")
```

**Responsibilities:**
- HTTP requests to Langfuse API
- Authentication (Basic Auth)
- Retry logic with exponential backoff
- Cache integration

### 3. Prompt Clients

#### TextPromptClient

For simple string templates:

```ruby
prompt = TextPromptClient.new(api_response)
result = prompt.compile(name: "Alice")  # => "Hello Alice!"
```

#### ChatPromptClient

For chat/completion prompts:

```ruby
prompt = ChatPromptClient.new(api_response)
messages = prompt.compile(user: "Alice")
# => [{ role: :system, content: "..." }, { role: :user, content: "..." }]
```

**Responsibilities:**
- Wrap API response data
- Compile prompts with Mustache
- Provide metadata access

### 4. Caching Layer

Two backends with same interface:

#### PromptCache (In-Memory)

```ruby
cache = Langfuse::PromptCache.new(ttl: 60, max_size: 1000)
cache.set(key, value)
cached = cache.get(key)
```

**Features:**
- Thread-safe with Monitor
- TTL expiration
- LRU eviction

#### RailsCacheAdapter (Distributed)

```ruby
adapter = Langfuse::RailsCacheAdapter.new(ttl: 60)
adapter.set(key, value)
cached = adapter.get(key)
```

**Features:**
- Wraps Rails.cache (Redis/Memcached)
- Distributed locks for stampede protection
- Exponential backoff

### 5. Main Client (`Langfuse::Client`)

User-facing API:

```ruby
client = Langfuse::Client.new(config)
prompt = client.get_prompt("name")
text = client.compile_prompt("name", variables: { name: "Alice" })
```

**Responsibilities:**
- Factory for prompt clients
- Cache backend selection
- High-level API methods

### 6. Tracing Layer (OpenTelemetry-based)

#### Tracer

```ruby
Langfuse.trace(name: "user-request") do |trace|
  trace.generation(name: "gpt4", model: "gpt-4") do |gen|
    gen.output = "Response"
    gen.usage = { prompt_tokens: 10, completion_tokens: 20 }
  end
end
```

#### Exporter

Converts OpenTelemetry spans to Langfuse events:

```ruby
exporter = Langfuse::Exporter.new(public_key, secret_key)
# Automatically called by OTel BatchSpanProcessor
```

**Responsibilities:**
- Convert OTel spans → Langfuse ingestion format
- Handle trace/span/generation types
- Batch export for efficiency

## Key Design Decisions

### 1. OpenTelemetry Foundation for Tracing

**Decision:** Build tracing on OpenTelemetry instead of custom implementation

**Why?**
- Industry standard (CNCF)
- Automatic distributed tracing (W3C Trace Context)
- Works with existing APM tools (Datadog, New Relic, etc.)
- Battle-tested context propagation

**Trade-offs:**
- ✅ More robust, future-proof
- ✅ Automatic distributed tracing
- ❌ ~10 additional gem dependencies
- ❌ Slightly more complex setup

### 2. Dual Cache Backend

**Decision:** Support both in-memory and Rails.cache backends

**Why?**
- In-memory: Perfect for single-process apps, scripts, small deployments
- Rails.cache: Essential for large multi-process deployments (100+ processes)

**Trade-offs:**
- ✅ Flexibility for different use cases
- ✅ Zero external dependencies by default
- ❌ More code to maintain
- ❌ Two code paths to test

### 3. Stampede Protection via Distributed Locks

**Decision:** Use Redis atomic operations for stampede protection

**Why?**
- Prevents thundering herd (1,200 simultaneous API calls → 1 call)
- Critical for large-scale deployments
- Works automatically with Rails.cache backend

**Trade-offs:**
- ✅ Massive performance improvement at scale
- ✅ Automatic - no user configuration needed
- ❌ Only works with Rails.cache backend
- ❌ Slight latency increase for waiting processes

### 4. Mustache for Variable Substitution

**Decision:** Use Mustache templating instead of ERB or custom solution

**Why?**
- Logic-less (no code execution = secure)
- Same syntax as Langfuse JavaScript SDK (consistency)
- Well-tested, mature library
- Supports nested objects, arrays, conditionals

**Alternatives considered:**
- ERB: Too powerful, security concerns
- String interpolation: Not flexible enough
- Custom: Reinventing the wheel

### 5. Flat API Surface

**Decision:** All methods on `Client`, not nested managers

**Why?**
- Inspired by LaunchDarkly Ruby SDK
- Simpler mental model
- Better IDE autocomplete
- Fewer classes to remember

**Example:**
```ruby
# ✅ Flat API
client.get_prompt("name")
client.compile_prompt("name", variables: {})

# ❌ Nested (rejected)
client.prompts.get("name")
client.prompts.compile("name", variables: {})
```

### 6. Global Configuration Singleton

**Decision:** `Langfuse.configure` block pattern with global client

**Why?**
- Rails-friendly (feels natural in initializers)
- Reduces boilerplate (don't pass client everywhere)
- Thread-safe singleton pattern
- Easy to reset for testing

**Trade-offs:**
- ✅ Convenient for most use cases
- ✅ Follows Rails conventions
- ❌ Global state (can be problematic in tests)
- ✅ Mitigated with `Langfuse.reset!` method

## Data Flow

### Prompt Fetching

```
User Code
  └─> Client.get_prompt("name")
       ├─> Check cache (PromptCache or RailsCacheAdapter)
       │    ├─> Cache HIT: Return cached prompt (~1ms)
       │    └─> Cache MISS: Continue to API
       ├─> ApiClient.get_prompt("name")
       │    ├─> Faraday HTTP request with retry
       │    ├─> Basic Auth header
       │    └─> Parse JSON response
       ├─> Cache response
       └─> Return TextPromptClient or ChatPromptClient
```

### Stampede Protection (Rails.cache only)

```
Cache expires → Multiple processes request same prompt
  └─> Process 1: Acquires distributed lock (Redis)
       ├─> Fetches from API
       ├─> Populates cache
       └─> Releases lock
  └─> Processes 2-N: Wait with exponential backoff
       ├─> 50ms, 100ms, 200ms
       ├─> Read from cache (populated by Process 1)
       └─> Return cached prompt

Result: 1 API call instead of N
```

### LLM Tracing

```
User Code
  └─> Langfuse.trace(name: "query") do |trace|
       ├─> Langfuse::Tracer creates OTel root span
       └─> trace.generation(name: "gpt4", model: "gpt-4") do |gen|
            ├─> Langfuse::Generation wraps OTel child span
            ├─> Sets Langfuse attributes (model, type="generation")
            └─> gen.usage = {...} → Sets token attributes
       ├─> OTel BatchSpanProcessor collects spans
       └─> Langfuse::Exporter converts spans to events
            ├─> Convert OTel span → Langfuse ingestion format
            ├─> Batch events (50 spans per batch)
            └─> POST /api/public/ingestion
```

## Technology Choices

### HTTP Client: Faraday

**Why Faraday?**
- Industry standard for Ruby HTTP
- Middleware architecture (retry, logging, etc.)
- Well-tested and maintained
- Flexible adapter support

### Templating: Mustache

**Why Mustache?**
- Logic-less (secure)
- Matches Langfuse JavaScript SDK
- Supports complex data structures
- Mature and stable

### Caching: Monitor + Rails.cache

**Why Monitor?**
- Built into Ruby standard library
- Simple, thread-safe synchronization
- No external dependencies

**Why Rails.cache?**
- Standard Rails pattern
- Works with Redis, Memcached, etc.
- Distributed caching built-in

### Tracing: OpenTelemetry

**Why OpenTelemetry?**
- CNCF standard for distributed tracing
- Automatic context propagation
- Works with existing APM tools
- Future-proof (industry direction)

## Performance Considerations

### Cache Hit Rate

- **In-memory**: ~1ms
- **Rails.cache (Redis)**: ~1-2ms
- **API call**: ~100ms

**Target:** >99% cache hit rate in production

### Memory Usage

- **In-memory cache**: ~10KB per prompt × max_size × num_processes
- **Rails.cache**: Single copy in Redis (shared)

### Concurrency

- **In-memory**: Monitor-based locking (minimal contention)
- **Rails.cache**: Redis atomic operations (high concurrency)

## Future Enhancements

See [docs/future-enhancements/](future-enhancements/) for detailed designs:

- **Stale-While-Revalidate**: Background cache refresh for even lower latency
- **Cost Tracking**: Automatic LLM cost calculation
- **Automatic LLM Client Wrappers**: Zero-boilerplate tracing for OpenAI, Anthropic

## Additional Resources

- [Main README](../README.md) - Getting started guide
- [Caching Guide](CACHING.md) - Detailed caching documentation
- [Tracing Guide](TRACING.md) - LLM observability guide
- [Rails Integration](RAILS.md) - Rails-specific patterns

## Questions?

Open an issue on [GitHub](https://github.com/langfuse/langfuse-ruby/issues) if you have architecture questions.
