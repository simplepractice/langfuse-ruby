# Langfuse Ruby - Tracing Implementation Progress

**Started:** 2025-10-15
**Current Phase:** T3 Complete - OpenTelemetry Integration Ready
**Last Updated:** 2025-10-15

---

## Quick Status

| Phase | Status | Completion | Tests |
|-------|--------|------------|-------|
| T0: OpenTelemetry Setup | 🟢 Complete | 100% | 8/8 passing |
| T1: Langfuse Exporter | 🟢 Complete | 100% | 38/38 passing |
| T2: Ruby API Wrapper | 🟢 Complete | 100% | 26/26 passing |
| T3: Async Processing | 🟢 Complete | 100% | 21/21 passing |
| T4: Prompt Linking | ⬜ Not Started | 0% | 0 tests |
| T5: Cost Tracking | ⬜ Not Started | 0% | 0 tests |
| T6: Distributed Tracing | ⬜ Not Started | 0% | 0 tests |
| T7: APM Integration | ⬜ Not Started | 0% | 0 tests |
| T8: Advanced Features | ⬜ Not Started | 0% | 0 tests |
| T9: Rails Integration | ⬜ Not Started | 0% | 0 tests |
| T10: Documentation & Polish | ⬜ Not Started | 0% | 0 tests |

**Overall Test Status:** 314 tests passing (93 tracing-specific)

**Legend:**
- ⬜ Not Started
- 🔵 In Progress
- 🟢 Complete
- 🟡 Blocked

---

## Architecture Overview

The tracing implementation is built on **OpenTelemetry** as the foundation:

```
┌─────────────────────────────────────────────────────────────┐
│ User Code (Langfuse.trace / Langfuse::Tracer)              │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Ruby API Wrapper (Trace, Span, Generation)                 │
│ - Block-based API                                           │
│ - Auto-linking prompts                                      │
│ - Setters for output, usage, metadata                      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ OpenTelemetry SDK                                           │
│ - TracerProvider                                            │
│ - BatchSpanProcessor (async) or SimpleSpanProcessor (sync) │
│ - W3C Trace Context propagation                            │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Langfuse::Exporter (Custom OTel Exporter)                  │
│ - Converts OTel spans → Langfuse events                    │
│ - Maps trace/span/generation types                         │
│ - Handles attributes, timestamps, IDs                      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Langfuse::IngestionClient                                  │
│ - HTTP POST to /api/public/ingestion                       │
│ - Batch ingestion                                           │
│ - Retry logic for transient errors                         │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
                   Langfuse Cloud API
```

---

## Phase Summaries

### ✅ Phase T0: OpenTelemetry Setup (Complete)

**Goal:** Verify OpenTelemetry SDK works correctly

**What We Built:**
- Added OTel dependencies to gemspec (`opentelemetry-api`, `opentelemetry-sdk`, `opentelemetry-common`)
- Ran `bundle install` successfully
- Created comprehensive integration tests (`spec/langfuse/otel_integration_spec.rb`)
- 8 tests covering basic OTel functionality, span creation, attributes, nesting, events, timestamps

**Files Created:**
- `spec/langfuse/otel_integration_spec.rb` (8 tests)

**Key Learnings:**
- OTel span IDs are binary - need `unpack1("H*")` to convert to hex
- `span.to_span_data` must be called after span ends, not during
- W3C Trace Context requires proper OTel setup to inject headers

**Test Results:** 8/8 passing

---

### ✅ Phase T1: Langfuse Exporter (Complete)

**Goal:** Build custom OpenTelemetry exporter that converts OTel spans to Langfuse ingestion events

**What We Built:**

#### 1. IngestionClient (`lib/langfuse/ingestion_client.rb`)
- HTTP client for POST /api/public/ingestion
- Basic Auth with public_key:secret_key
- Batch ingestion of events
- Retry logic for transient errors (408, 429, 500, 502, 503, 504, timeout)
- Faraday with exponential backoff

#### 2. Exporter (`lib/langfuse/exporter.rb`)
- Custom OpenTelemetry `SpanExporter` implementation
- Implements OTel interface: `export`, `force_flush`, `shutdown`
- Converts 3 span types:
  - `trace-create` for traces (type="trace")
  - `span-create` for spans (type="span")
  - `generation-create` for LLM calls (type="generation")
- Extracts attributes from OTel spans
- Formats binary IDs to hex: `span_id.unpack1("H*")`
- Formats timestamps from nanoseconds to ISO 8601
- Parses JSON attributes safely
- Graceful error handling (returns FAILURE, logs but doesn't crash)

**Files Created:**
- `lib/langfuse/ingestion_client.rb`
- `lib/langfuse/exporter.rb`
- `spec/langfuse/ingestion_client_spec.rb` (23 tests)
- `spec/langfuse/exporter_spec.rb` (15 tests)

**Test Results:** 38/38 passing (23 ingestion + 15 exporter)

---

### ✅ Phase T2: Ruby API Wrapper (Complete)

**Goal:** Create idiomatic Ruby API that hides OTel complexity

**What We Built:**

#### 1. Configuration (`lib/langfuse/config.rb`)
- Added tracing configuration attributes:
  - `tracing_enabled` (default: false)
  - `tracing_async` (default: true)
  - `batch_size` (default: 50)
  - `flush_interval` (default: 10 seconds)
  - `job_queue` (default: :default)

#### 2. Tracer (`lib/langfuse/tracer.rb`)
- Ruby wrapper around OpenTelemetry tracer
- Main method: `trace(name:, user_id:, session_id:, metadata:, tags:, context:)`
- Hides OTel complexity behind Ruby blocks
- Converts Ruby kwargs to OTel attributes with "langfuse." prefix
- Handles distributed tracing context

#### 3. Trace (`lib/langfuse/trace.rb`)
- Wrapper around OTel span representing a trace
- Methods:
  - `span(name:, input:, metadata:, level:)` - Create child span
  - `generation(name:, model:, input:, metadata:, model_parameters:, prompt:)` - Create LLM call
  - `event(name:, input:, level:)` - Add event to trace
  - `current_span` - Access underlying OTel span
  - `inject_context` - Get W3C Trace Context headers
- Auto-links prompts: detects `TextPromptClient`/`ChatPromptClient` and extracts name/version

#### 4. Span (`lib/langfuse/span.rb`)
- Wrapper for span operations
- Methods:
  - `span(name:, ...)` - Create nested child span
  - `generation(name:, model:, ...)` - Create LLM call
  - `event(name:, ...)` - Add event
  - `output=`, `metadata=`, `level=` - Setters
  - `current_span` - Access underlying OTel span

#### 5. Generation (`lib/langfuse/generation.rb`)
- Wrapper for LLM-specific operations
- Methods:
  - `output=` - Set generation output
  - `usage=` - Set token usage statistics
  - `metadata=` - Set metadata
  - `level=` - Set log level
  - `event(name:, ...)` - Add event
  - `current_span` - Access underlying OTel span

#### 6. Global API (`lib/langfuse.rb`)
- Added `Langfuse.tracer` - Returns global singleton tracer
- Added `Langfuse.trace(name:, ...)` - Convenience method
- Updated `Langfuse.reset!` - Resets tracer

**Files Created:**
- `lib/langfuse/tracer.rb`
- `lib/langfuse/trace.rb`
- `lib/langfuse/span.rb`
- `lib/langfuse/generation.rb`
- `spec/langfuse/ruby_api_spec.rb` (26 tests)

**Files Modified:**
- `lib/langfuse.rb` - Added requires and global methods
- `lib/langfuse/config.rb` - Added tracing config

**Example Usage:**
```ruby
Langfuse.trace(name: "user-request", user_id: "user-123") do |trace|
  trace.span(name: "retrieval", input: { query: "..." }) do |span|
    span.output = { results: [...] }
  end

  trace.generation(name: "gpt4", model: "gpt-4") do |gen|
    gen.output = "Hello!"
    gen.usage = { prompt_tokens: 100, completion_tokens: 50 }
  end
end
```

**Test Results:** 26/26 passing

---

### ✅ Phase T3: Async Processing & OTel Integration (Complete)

**Goal:** Set up OpenTelemetry infrastructure with auto-initialization and async/sync processing

**What We Built:**

#### 1. OTel Setup Module (`lib/langfuse/otel_setup.rb`)
- Singleton module for OTel lifecycle management
- `setup(config)` - Initialize OTel with Langfuse exporter
- `shutdown(timeout:)` - Gracefully shutdown and flush
- `force_flush(timeout:)` - Flush pending spans
- `initialized?` - Check if OTel is initialized
- Creates `BatchSpanProcessor` (async) or `SimpleSpanProcessor` (sync) based on config
- Sets global `TracerProvider` for all traces

#### 2. Auto-initialization (`lib/langfuse.rb`)
- Updated `Langfuse.configure` - Auto-initializes OTel when `tracing_enabled: true`
- Added `Langfuse.shutdown(timeout:)` - Shutdown OTel and flush traces
- Added `Langfuse.force_flush(timeout:)` - Force flush pending traces
- Updated `Langfuse.reset!` - Properly shuts down OTel

**Files Created:**
- `lib/langfuse/otel_setup.rb`
- `spec/langfuse/otel_setup_spec.rb` (21 tests)

**Files Modified:**
- `lib/langfuse.rb` - Auto-initialization, shutdown, force_flush

**Configuration Example:**
```ruby
# In a Rails initializer
Langfuse.configure do |config|
  config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
  config.secret_key = ENV['LANGFUSE_SECRET_KEY']
  config.tracing_enabled = true   # Auto-initializes OTel
  config.tracing_async = true     # Use BatchSpanProcessor (default)
  config.batch_size = 50
  config.flush_interval = 10
end

# Graceful shutdown
at_exit { Langfuse.shutdown }
```

**How It Works:**
1. `Langfuse.configure` with `tracing_enabled: true` calls `OtelSetup.setup(config)`
2. OtelSetup creates Langfuse exporter
3. Creates BatchSpanProcessor (async) or SimpleSpanProcessor (sync)
4. Sets global TracerProvider
5. All traces now export to Langfuse automatically

**Test Results:** 21/21 passing

---

## Remaining Phases

### Phase T4: Prompt Linking (Not Started)

**Goal:** Automatically link prompts to generations

**Planned Features:**
- Already implemented basic auto-linking in `Trace#generation` and `Span#generation`
- Detects `TextPromptClient`/`ChatPromptClient` via duck typing (`respond_to?(:name)` and `respond_to?(:version)`)
- Extracts `prompt_name` and `prompt_version` attributes

**Status:** Basic implementation done in T2, may need additional testing/documentation

---

### Phase T5: Cost Tracking (Not Started)

**Goal:** Calculate LLM costs based on usage

**Planned Features:**
- Model pricing database
- Automatic cost calculation from usage tokens
- Cost attributes on generations
- Total cost rollup at trace level

---

### Phase T6: Distributed Tracing (Not Started)

**Goal:** W3C Trace Context propagation across services

**Planned Features:**
- Already implemented `inject_context` method in `Trace` class
- Automatically works via OTel's W3C propagation
- May need examples and documentation

**Status:** Basic implementation done in T2, needs documentation

---

### Phase T7: APM Integration (Not Started)

**Goal:** Integrate with Rails, Rack, Sinatra, etc.

**Planned Features:**
- Automatic trace creation for web requests
- Middleware for Rack applications
- Rails integration (controller instrumentation)
- Background job instrumentation (Sidekiq, GoodJob)

---

### Phase T8: Advanced Features (Not Started)

**Goal:** Additional Langfuse features

**Planned Features:**
- Scores and feedback
- Custom metadata
- Tags
- User properties
- Session tracking

---

### Phase T9: Rails Integration (Not Started)

**Goal:** Make gem Rails-friendly

**Planned Features:**
- Generators for initializers
- Railtie for automatic setup
- ActiveSupport instrumentation
- ActionMailer integration

---

### Phase T10: Documentation & Polish (Not Started)

**Goal:** Production-ready gem

**Planned Features:**
- Comprehensive README
- API documentation (YARD)
- Usage examples
- Performance benchmarks
- Security audit
- 1.0 release preparation

---

## Test Coverage Summary

**Total Tests:** 314 passing

**By Category:**
- Prompt Management: 221 tests (99.6% coverage)
- Tracing (T0-T3): 93 tests
  - OTel Integration: 8 tests
  - Ingestion Client: 23 tests
  - Exporter: 15 tests
  - Ruby API Wrapper: 26 tests
  - OTel Setup: 21 tests

**Coverage:** 60.9% (324/532 lines)
- Lower than prompt management (99.6%) because tracing code is newer
- Target: >90% by Phase T10

---

## Design Decisions

### 2025-10-15 - OpenTelemetry Foundation
**Decision:** Use OpenTelemetry as the foundation for tracing instead of custom implementation
**Context:** User explicitly requested OTel support after initial design didn't include it
**Benefits:**
- Standard distributed tracing protocol (W3C Trace Context)
- Interoperability with other observability tools
- Battle-tested span management and context propagation
- Easy integration with APM tools (Datadog, New Relic, Honeycomb)

### 2025-10-15 - ActiveJob Instead of Sidekiq
**Decision:** Use ActiveJob abstraction instead of Sidekiq specifically
**Context:** User feedback: "can we use ActiveJob instead of sidekiq specifically just in case other projects don't use sidekiq?"
**Benefits:**
- Works with any ActiveJob backend (Sidekiq, Resque, GoodJob, Delayed Job)
- More portable across different Rails projects
- Simpler for non-Rails projects (just use sync mode)

### 2025-10-15 - Default Queue :default
**Decision:** Changed default job queue from `:langfuse` to `:default`
**Context:** User feedback: "I think :langfuse is a bad default because, for sidekiq, if that queue is not specified in the sidekiq config, the jobs won't get processed"
**Benefits:**
- Works out of the box with all ActiveJob backends
- No additional configuration required
- Users can still customize via `config.job_queue = :custom`

### 2025-10-15 - Block-Based API
**Decision:** Use Ruby blocks for scoped tracing operations
**Why:** Idiomatic Ruby pattern, automatic resource cleanup, clear scope boundaries
**Example:**
```ruby
Langfuse.trace(name: "request") do |trace|
  # trace is automatically finished when block exits
end
```

### 2025-10-15 - Attribute Prefix "langfuse."
**Decision:** Namespace all Langfuse-specific OTel attributes with "langfuse." prefix
**Why:** Prevents conflicts with other OTel instrumentation, clearly identifies Langfuse data
**Examples:** `langfuse.type`, `langfuse.model`, `langfuse.user_id`

---

## Next Steps

**Immediate:**
- ✅ Phase T3 Complete - OpenTelemetry integration working
- Choose next phase: T4 (Prompt Linking), T5 (Cost Tracking), or T6 (Distributed Tracing)

**Short-term:**
- T4-T6: Core tracing features
- Write comprehensive examples
- Update README with tracing usage

**Long-term:**
- T7-T9: Rails/APM integration
- T10: Documentation and 1.0 release
- Consider extracting tracing to separate gem (langfuse-tracing)

---

## Related Files

- **Design:** [TRACING_DESIGN.md](TRACING_DESIGN.md) - Complete tracing design specification
- **Prompt Management:** [PROGRESS.md](PROGRESS.md) - Prompt management progress
- **Implementation Plan:** [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) - Original roadmap for prompt features
