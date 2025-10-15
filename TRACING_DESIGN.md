# Langfuse Ruby SDK - Tracing & Observability Design (OpenTelemetry-Based)

**Status:** Draft Design Document (Revised for OpenTelemetry)
**Created:** 2025-10-15
**Revised:** 2025-10-15
**Author:** Noah Fisher

---

## Table of Contents

1. [Overview](#overview)
2. [Why OpenTelemetry?](#why-opentelemetry)
3. [Design Principles](#design-principles)
4. [Architecture](#architecture)
5. [API Design](#api-design)
6. [Data Model (OTel + Langfuse)](#data-model-otel--langfuse)
7. [OpenTelemetry Integration](#opentelemetry-integration)
8. [Ingestion Architecture](#ingestion-architecture)
9. [Distributed Tracing](#distributed-tracing)
10. [Prompt-to-Trace Linking](#prompt-to-trace-linking)
11. [Cost & Token Tracking](#cost--token-tracking)
12. [APM Integration](#apm-integration)
13. [Error Handling & Resilience](#error-handling--resilience)
14. [Implementation Phases](#implementation-phases)

---

## Overview

This document defines the tracing and observability features for the Langfuse Ruby SDK. These features complement the existing prompt management functionality (Phases 0-5 complete) by providing comprehensive LLM observability built on **OpenTelemetry**, the CNCF standard for distributed tracing.

### Goals

1. **OpenTelemetry Foundation**: Build on industry-standard OTel SDK for tracing
2. **Rails-Friendly**: Seamless integration with Rails applications and ActiveJob
3. **Distributed Tracing**: Automatic context propagation across services
4. **APM Integration**: Traces appear in Datadog, New Relic, Honeycomb, etc.
5. **Ruby-First API**: Idiomatic blocks and patterns, despite OTel underneath
6. **Automatic Linking**: Connect prompts to traces automatically
7. **Production-Ready**: Batching, retries, circuit breakers, graceful degradation

### Non-Goals (for v1.0)

- Real-time streaming of traces (future enhancement)
- Client-side tracing (browser SDK)
- Custom OTel instrumentations (use existing gems)

---

## Why OpenTelemetry?

### Rationale

After researching Langfuse's Python SDK, it became clear that **Langfuse is built on top of OpenTelemetry**, not as a separate system:

> "Context Propagation: **OpenTelemetry automatically handles** the propagation of the current trace and span context." - Langfuse Python SDK docs

**Benefits of OTel Foundation:**

1. **Industry Standard** - CNCF standard, used by every major APM vendor
2. **Context Propagation** - Automatic distributed tracing via W3C Trace Context
3. **Ecosystem Integration** - Works with existing Ruby instrumentation (Rails, Sidekiq, HTTP)
4. **Less Code** - Use OTel's span lifecycle, we add Langfuse-specific attributes
5. **Consistency** - Matches Python/TypeScript SDK architecture
6. **APM Correlation** - Langfuse traces appear alongside infrastructure traces

**Trade-offs:**

- ✅ More robust, future-proof
- ✅ Automatic distributed tracing
- ✅ Industry ecosystem support
- ❌ Adds ~10 OTel gem dependencies
- ❌ Slightly more complex setup
- ⚖️ Basic usage stays simple for developers

---

## Design Principles

### 1. OpenTelemetry Foundation

- **Build on OTel SDK** for span/trace management
- **Create custom Exporter** to convert OTel spans → Langfuse events
- **Use OTel Context** for propagation (not custom thread-local)
- **Add Langfuse extensions** as span attributes (model, tokens, prompts, costs)

### 2. Consistency with Existing Architecture

Follow the same patterns established in prompt management:
- **Flat API**: Methods on `Client`, not nested managers
- **Global Configuration**: `Langfuse.configure` pattern
- **Thread-Safe**: OTel handles this for us
- **Minimal Dependencies**: Only add what's necessary
- **Ruby Conventions**: snake_case, keyword arguments, blocks

### 3. Ruby-First API (Hide OTel Complexity)

```ruby
# ✅ GOOD - Ruby idioms (OTel underneath)
Langfuse.trace("user-query") do |trace|
  trace.generation("llm-call", model: "gpt-4") do |gen|
    gen.input = [{ role: "user", content: "Hello" }]
    gen.output = call_openai(...)
  end
end

# ❌ AVOID - Exposing OTel internals
tracer = OpenTelemetry.tracer_provider.tracer("langfuse")
span = tracer.start_span("user-query")
```

### 4. Async by Default

- Background processing via ActiveJob (works with Sidekiq, Resque, Delayed Job, GoodJob, etc.)
- Batching to reduce API calls
- Graceful degradation if ActiveJob is unavailable
- Sync mode for debugging/testing
- Configurable queue name

### 5. Developer Experience

- Simple for basic use cases (hide OTel)
- Powerful for advanced scenarios (expose OTel when needed)
- Clear error messages
- Automatic metadata capture
- Minimal boilerplate

---

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Application Code                          │
│  Langfuse.trace(...) { |t| t.generation(...) }              │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              Langfuse Ruby API (Block-based)                │
│  • Langfuse::Client                                         │
│  • Langfuse::Tracer (wrapper around OTel)                   │
│  • Langfuse::Generation (adds model, tokens, prompts)       │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│           OpenTelemetry SDK (Core Tracing)                  │
│  • Tracer: Creates spans                                    │
│  • Context: Propagates trace/span context                   │
│  • Span: Time-bounded operations                            │
│  • Attributes: Key-value metadata                           │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│        Langfuse Exporter (OTel → Langfuse Events)           │
│  • Converts OTel spans → Langfuse ingestion format          │
│  • Adds Langfuse-specific fields (prompt, costs)            │
│  • Batches events for ingestion API                         │
└────────────────────┬────────────────────────────────────────┘
                     │
        ┌────────────┴───────────┐
        │                        │
        ▼                        ▼
┌──────────────┐      ┌──────────────────────┐
│ Sync Export  │      │  Async Export        │
│ (Test/Debug) │      │  (ActiveJob)         │
└──────┬───────┘      └──────────┬───────────┘
       │                         │
       └────────────┬────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│         Langfuse Ingestion API                              │
│  POST /api/public/ingestion (batch events)                  │
└─────────────────────────────────────────────────────────────┘
```

### Component Breakdown

1. **Langfuse Ruby API** - Idiomatic Ruby blocks, hide OTel complexity
2. **OpenTelemetry SDK** - Handle span lifecycle, context propagation
3. **Langfuse Exporter** - Custom OTel exporter that converts spans to Langfuse events
4. **Ingestion Client** - HTTP client with batching, retries, circuit breaker
5. **ActiveJob Worker** - Async background processing (optional, works with any ActiveJob backend)

---

## API Design

### Core Concepts (Same as Before)

**Traces** → The root container for an LLM interaction (OTel trace)
**Spans** → Time-bounded operations (OTel span)
**Generations** → LLM calls (OTel span with extra attributes)
**Events** → Point-in-time markers (OTel span events)
**Scores** → Evaluations (custom Langfuse concept, sent separately)

### Hierarchy (OTel Spans)

```
OTel Trace
├── OTel Span (type: "span", name: "document-retrieval")
│   └── OTel Span (type: "generation", model: "text-embedding-ada-002")
├── OTel Span (type: "span", name: "llm-processing")
│   └── OTel Span (type: "generation", model: "gpt-4")
├── OTel Event (name: "user-feedback")
└── Custom Score (sent via Langfuse API)
```

---

## API Examples

### Example 1: Basic Trace with Generation

```ruby
# Simple block-based API (OTel underneath)
Langfuse.trace(name: "chat-completion", user_id: "user-123") do |trace|
  trace.generation(
    name: "openai-call",
    model: "gpt-4",
    input: [{ role: "user", content: "Hello!" }]
  ) do |gen|
    response = openai_client.chat(...)

    gen.output = response.choices.first.message.content
    gen.usage = {
      prompt_tokens: response.usage.prompt_tokens,
      completion_tokens: response.usage.completion_tokens,
      total_tokens: response.usage.total_tokens
    }
  end
end

# Under the hood:
# 1. OTel creates a root span with name "chat-completion"
# 2. OTel creates child span with name "openai-call"
# 3. Langfuse adds attributes: model="gpt-4", type="generation", usage={...}
# 4. Langfuse Exporter converts to ingestion events
```

### Example 2: Nested Spans for RAG Pipeline

```ruby
Langfuse.trace(name: "rag-query", session_id: "session-456") do |trace|
  # Document retrieval span (OTel span)
  docs = trace.span(name: "retrieval", input: { query: "ML basics" }) do |span|
    # Embedding generation (OTel span with type="generation")
    embedding = span.generation(
      name: "embed-query",
      model: "text-embedding-ada-002",
      input: "ML basics"
    ) do |gen|
      result = openai_client.embeddings(...)
      gen.output = result.embedding
      gen.usage = { total_tokens: result.usage.total_tokens }
      result.embedding
    end

    # Retrieve from vector DB
    vector_db.search(embedding, limit: 5)
  end

  # LLM generation span
  trace.span(name: "llm-generation") do |span|
    prompt = build_rag_prompt(docs)

    span.generation(
      name: "gpt4-completion",
      model: "gpt-4",
      input: prompt,
      metadata: { num_docs: docs.size }
    ) do |gen|
      response = openai_client.chat(...)
      gen.output = response.choices.first.message.content
      gen.usage = {
        prompt_tokens: response.usage.prompt_tokens,
        completion_tokens: response.usage.completion_tokens
      }
    end
  end

  # Track user feedback event (OTel span event)
  trace.event(
    name: "user-feedback",
    input: { rating: "thumbs_up" }
  )

  # Add quality score (custom Langfuse concept)
  trace.score(name: "helpfulness", value: 0.95)
end

# OTel automatically handles:
# - Parent-child span relationships
# - Timestamps (start_time, end_time)
# - Context propagation within the trace
```

### Example 3: Distributed Tracing Across Services

```ruby
# Service A (API Gateway)
def handle_request
  Langfuse.trace(name: "api-request", user_id: "user-123") do |trace|
    # Make HTTP request to Service B
    # OTel automatically injects W3C Trace Context headers!
    response = HTTParty.get(
      "http://service-b/process",
      headers: trace.inject_context  # W3C traceparent header
    )

    trace.event(name: "downstream-call", output: response.code)
  end
end

# Service B (Processing Service)
def process_request
  # Extract context from headers (W3C Trace Context)
  context = Langfuse.extract_context(request.headers)

  # This trace is automatically linked to the parent trace in Service A!
  Langfuse.trace(name: "process-data", context: context) do |trace|
    trace.generation(name: "llm-call", model: "gpt-4") do |gen|
      # ... LLM processing
    end
  end
end

# Result: Single unified trace across both services!
# Service A → Service B (parent-child relationship preserved)
```

### Example 4: APM Integration (Datadog Example)

```ruby
# When both Langfuse and Datadog are configured:

Langfuse.trace(name: "user-query") do |trace|
  trace.generation(name: "gpt4", model: "gpt-4") do |gen|
    # Call external API
    response = HTTParty.get("https://api.example.com/data")
    # ... LLM processing
  end
end

# Result in Datadog APM:
# ┌─ Trace: user-query (Langfuse + Datadog)
# │  ├─ Span: gpt4 (Langfuse generation)
# │  │  └─ Attributes: model=gpt-4, tokens=225, cost=0.00525
# │  └─ Span: http.request (Datadog automatic instrumentation)
# │     └─ URL: https://api.example.com/data
# └─ All correlated with the same trace_id!
```

### Example 5: Advanced - Direct OTel Access

```ruby
# For advanced users who need OTel directly
Langfuse.trace(name: "complex-workflow") do |trace|
  # Access underlying OTel span
  otel_span = trace.current_span

  # Add custom OTel attributes
  otel_span.set_attribute("custom.metric", 42)

  # Use OTel status
  otel_span.status = OpenTelemetry::Trace::Status.error("Failed")

  # Still use Langfuse convenience methods
  trace.generation(name: "gpt4", model: "gpt-4") do |gen|
    # ...
  end
end
```

---

## Data Model (OTel + Langfuse)

### How OTel Spans Map to Langfuse Concepts

| Langfuse Concept | OpenTelemetry Representation | Langfuse-Specific Attributes |
|------------------|------------------------------|------------------------------|
| **Trace** | OTel Trace (root span) | `user_id`, `session_id`, `tags`, `public` |
| **Span** | OTel Span | `langfuse.type="span"`, `input`, `output`, `level` |
| **Generation** | OTel Span | `langfuse.type="generation"`, `model`, `usage`, `prompt_name`, `prompt_version` |
| **Event** | OTel Span Event | `name`, `input`, `output` |
| **Score** | Custom (not OTel) | Sent separately via Langfuse API |

### OTel Span Attributes for Langfuse

**Common Attributes (all spans):**
```ruby
{
  "langfuse.type" => "span",  # or "generation"
  "langfuse.trace_id" => "trace-abc123",
  "langfuse.user_id" => "user-456",
  "langfuse.session_id" => "session-789",
  "langfuse.metadata" => { ... },  # JSON
  "langfuse.input" => { ... },     # JSON
  "langfuse.output" => { ... },    # JSON
  "langfuse.level" => "default"    # debug, default, warning, error
}
```

**Generation-Specific Attributes:**
```ruby
{
  "langfuse.type" => "generation",
  "langfuse.model" => "gpt-4",
  "langfuse.model_parameters" => { temperature: 0.7 },  # JSON
  "langfuse.usage.prompt_tokens" => 100,
  "langfuse.usage.completion_tokens" => 50,
  "langfuse.usage.total_tokens" => 150,
  "langfuse.usage.total_cost" => 0.00525,  # Auto-calculated
  "langfuse.prompt_name" => "support-assistant",  # Auto-linked
  "langfuse.prompt_version" => 3,  # Auto-linked
  "langfuse.completion_start_time" => "2025-10-15T10:00:02.5Z"  # Streaming
}
```

### OTel Event Format

```ruby
# Span event (for user feedback, etc.)
span.add_event(
  "user-feedback",
  attributes: {
    "langfuse.input" => { feedback_type: "thumbs_up" }.to_json,
    "langfuse.level" => "default"
  },
  timestamp: Time.now
)
```

### Score (Separate from OTel)

Scores are sent as separate events to Langfuse API (not OTel):

```ruby
{
  type: "score-create",
  body: {
    id: "score-xyz",
    trace_id: "trace-abc",  # Link to OTel trace
    observation_id: "span-123",  # Link to OTel span
    name: "helpfulness",
    value: 0.95,
    comment: "Very helpful",
    data_type: "numeric"
  }
}
```

---

## OpenTelemetry Integration

### OTel Components We'll Use

1. **opentelemetry-sdk** - Core tracing SDK
2. **opentelemetry-api** - Public API
3. **opentelemetry-exporter-otlp** - (Optional) For OTel Collector
4. **opentelemetry-instrumentation-all** - (Optional) Auto-instrumentation

### Initialization

```ruby
require 'opentelemetry/sdk'
require 'langfuse/exporter'

# Initialize OpenTelemetry with Langfuse exporter
OpenTelemetry::SDK.configure do |c|
  c.service_name = 'my-rails-app'
  c.service_version = ENV['APP_VERSION']

  # Add Langfuse exporter
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      Langfuse::Exporter.new(
        public_key: ENV['LANGFUSE_PUBLIC_KEY'],
        secret_key: ENV['LANGFUSE_SECRET_KEY']
      )
    )
  )

  # Optionally add OTLP exporter for APM (Datadog, etc.)
  if ENV['OTEL_EXPORTER_OTLP_ENDPOINT']
    c.add_span_processor(
      OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
        OpenTelemetry::Exporter::OTLP::Exporter.new
      )
    )
  end
end
```

### Langfuse Wrapper Around OTel

```ruby
module Langfuse
  class Tracer
    def initialize(otel_tracer)
      @otel_tracer = otel_tracer
    end

    def trace(name:, **attributes, &block)
      # Create OTel span
      @otel_tracer.in_span(name, attributes: otel_attributes(attributes)) do |span|
        # Wrap in Langfuse::Trace for Ruby API
        trace_obj = Trace.new(span, attributes)
        yield(trace_obj)
      end
    end

    private

    def otel_attributes(attrs)
      # Convert Langfuse attributes to OTel format
      {
        "langfuse.type" => "trace",
        "langfuse.user_id" => attrs[:user_id],
        "langfuse.session_id" => attrs[:session_id],
        "langfuse.metadata" => attrs[:metadata].to_json
      }.compact
    end
  end
end
```

### Langfuse::Trace Class

```ruby
module Langfuse
  class Trace
    attr_reader :otel_span

    def initialize(otel_span, attributes = {})
      @otel_span = otel_span
      @attributes = attributes
    end

    def span(name:, **attrs, &block)
      # Create child OTel span
      tracer = OpenTelemetry.tracer_provider.tracer('langfuse')
      tracer.in_span(name, attributes: otel_attributes(attrs, type: "span")) do |span|
        span_obj = Span.new(span, attrs)
        yield(span_obj)
      end
    end

    def generation(name:, model:, **attrs, &block)
      tracer = OpenTelemetry.tracer_provider.tracer('langfuse')
      tracer.in_span(name, attributes: otel_attributes(attrs, type: "generation", model: model)) do |span|
        gen_obj = Generation.new(span, attrs.merge(model: model))
        yield(gen_obj)
      end
    end

    def event(name:, **attrs)
      @otel_span.add_event(name, attributes: {
        "langfuse.input" => attrs[:input].to_json,
        "langfuse.level" => attrs[:level] || "default"
      }.compact)
    end

    def score(name:, value:, **attrs)
      # Scores are sent separately (not OTel)
      ScoreBuffer.push(
        trace_id: @otel_span.context.trace_id.hex_id,
        name: name,
        value: value,
        **attrs
      )
    end

    def inject_context
      # For distributed tracing - inject W3C headers
      carrier = {}
      OpenTelemetry.propagation.inject(carrier)
      carrier
    end

    def current_span
      # For advanced users who need OTel directly
      @otel_span
    end

    private

    def otel_attributes(attrs, type:, model: nil)
      {
        "langfuse.type" => type,
        "langfuse.model" => model,
        "langfuse.input" => attrs[:input].to_json,
        "langfuse.metadata" => attrs[:metadata].to_json
      }.compact
    end
  end
end
```

---

## Ingestion Architecture

### Langfuse Exporter (OTel Custom Exporter)

```ruby
module Langfuse
  class Exporter
    def initialize(public_key:, secret_key:, **options)
      @public_key = public_key
      @secret_key = secret_key
      @buffer = EventBuffer.new
      @ingestion_client = IngestionClient.new(public_key, secret_key)
    end

    # Called by OTel BatchSpanProcessor
    def export(span_data_list, timeout: nil)
      events = span_data_list.map { |span| convert_span_to_event(span) }

      # Buffer events
      events.each { |event| @buffer.push(event) }

      # Trigger batch send if buffer is full
      flush_if_needed

      OpenTelemetry::SDK::Trace::Export::SUCCESS
    rescue StandardError => e
      Rails.logger.error("Langfuse export failed: #{e.message}")
      OpenTelemetry::SDK::Trace::Export::FAILURE
    end

    def force_flush(timeout: nil)
      events = @buffer.drain_all
      return if events.empty?

      @ingestion_client.send_batch(events)
    end

    def shutdown(timeout: nil)
      force_flush(timeout: timeout)
    end

    private

    def convert_span_to_event(span)
      attrs = span.attributes || {}
      type = attrs["langfuse.type"] || "span"

      case type
      when "trace"
        create_trace_event(span, attrs)
      when "span"
        create_span_event(span, attrs)
      when "generation"
        create_generation_event(span, attrs)
      end
    end

    def create_trace_event(span, attrs)
      {
        id: SecureRandom.uuid,
        timestamp: span.start_timestamp,
        type: "trace-create",
        body: {
          id: span.trace_id.hex_id,
          name: span.name,
          user_id: attrs["langfuse.user_id"],
          session_id: attrs["langfuse.session_id"],
          metadata: parse_json(attrs["langfuse.metadata"]),
          tags: attrs["langfuse.tags"],
          timestamp: span.start_timestamp
        }.compact
      }
    end

    def create_generation_event(span, attrs)
      {
        id: SecureRandom.uuid,
        timestamp: span.start_timestamp,
        type: "generation-create",
        body: {
          id: span.span_id.hex_id,
          trace_id: span.trace_id.hex_id,
          parent_observation_id: span.parent_span_id&.hex_id,
          name: span.name,
          model: attrs["langfuse.model"],
          input: parse_json(attrs["langfuse.input"]),
          output: parse_json(attrs["langfuse.output"]),
          model_parameters: parse_json(attrs["langfuse.model_parameters"]),
          usage: extract_usage(attrs),
          prompt_name: attrs["langfuse.prompt_name"],
          prompt_version: attrs["langfuse.prompt_version"],
          start_time: span.start_timestamp,
          end_time: span.end_timestamp,
          completion_start_time: attrs["langfuse.completion_start_time"],
          level: attrs["langfuse.level"] || "default",
          status_message: span.status&.description
        }.compact
      }
    end

    def extract_usage(attrs)
      return nil unless attrs["langfuse.usage.total_tokens"]

      {
        prompt_tokens: attrs["langfuse.usage.prompt_tokens"],
        completion_tokens: attrs["langfuse.usage.completion_tokens"],
        total_tokens: attrs["langfuse.usage.total_tokens"],
        total_cost: attrs["langfuse.usage.total_cost"]
      }.compact
    end

    def parse_json(json_string)
      JSON.parse(json_string) if json_string
    rescue JSON::ParserError
      nil
    end

    def flush_if_needed
      return unless @buffer.size >= config.batch_size

      events = @buffer.drain(max: config.batch_size)

      # Use ActiveJob if available, otherwise sync
      if async_enabled?
        IngestionJob.perform_later(events: events)
      else
        @ingestion_client.send_batch(events)
      end
    end

    def async_enabled?
      defined?(ActiveJob) && config.tracing_async
    end
  end
end
```

### ActiveJob Worker

```ruby
module Langfuse
  class IngestionJob < ActiveJob::Base
    queue_as { Langfuse.config.job_queue }

    retry_on StandardError, wait: :exponentially_longer, attempts: 3

    def perform(events:)
      client = IngestionClient.new(
        Langfuse.config.public_key,
        Langfuse.config.secret_key
      )

      client.send_batch(events)
    rescue StandardError => e
      Rails.logger.error("Langfuse ingestion failed: #{e.message}")
      # Re-raise to trigger ActiveJob retry
      raise
    end
  end
end
```

### Batch Request Format (Same as Before)

```ruby
# POST /api/public/ingestion
{
  batch: [
    {
      id: "event-123",
      timestamp: "2025-10-15T10:00:00.000Z",
      type: "trace-create",
      body: {
        id: "abc123def456",  # OTel trace_id
        name: "user-query",
        user_id: "user-456",
        metadata: { ... }
      }
    },
    {
      id: "event-124",
      timestamp: "2025-10-15T10:00:01.000Z",
      type: "generation-create",
      body: {
        id: "789xyz",  # OTel span_id
        trace_id: "abc123def456",  # OTel trace_id
        parent_observation_id: "parent-span-id",
        name: "openai-call",
        model: "gpt-4",
        input: [...],
        output: "...",
        usage: { ... }
      }
    }
  ]
}
```

---

## Distributed Tracing

### W3C Trace Context Propagation

OpenTelemetry automatically handles distributed tracing via W3C Trace Context headers:

**Header Format:**
```
traceparent: 00-<trace-id>-<span-id>-<flags>
tracestate: langfuse=<langfuse-specific-data>
```

### Automatic Propagation (HTTP Calls)

```ruby
# With opentelemetry-instrumentation-http installed:

Langfuse.trace(name: "api-request") do |trace|
  # OTel automatically injects traceparent header!
  response = HTTParty.get("http://service-b/api")

  # Downstream service sees:
  # traceparent: 00-abc123def456-789xyz-01
end
```

### Manual Context Injection/Extraction

```ruby
# Service A - Inject context
Langfuse.trace(name: "parent") do |trace|
  headers = trace.inject_context
  # => { "traceparent" => "00-abc123...", "tracestate" => "..." }

  HTTParty.get(url, headers: headers)
end

# Service B - Extract context
def handle_request
  context = Langfuse.extract_context(request.headers)

  Langfuse.trace(name: "child", context: context) do |trace|
    # Automatically linked to parent trace!
  end
end
```

### Implementation

```ruby
module Langfuse
  def self.extract_context(headers)
    carrier = headers.to_h
    OpenTelemetry.propagation.extract(carrier)
  end

  def self.trace(name:, context: nil, **attrs, &block)
    if context
      # Use extracted context as parent
      OpenTelemetry::Context.with_current(context) do
        tracer.trace(name: name, **attrs, &block)
      end
    else
      # Create new root trace
      tracer.trace(name: name, **attrs, &block)
    end
  end
end
```

---

## Prompt-to-Trace Linking

### Automatic Linking (Same as Before)

When a prompt is used in a generation, automatically capture as OTel attributes:

```ruby
prompt = Langfuse.client.get_prompt("support-assistant", version: 3)

Langfuse.trace(name: "support-query") do |trace|
  trace.generation(
    name: "response",
    model: "gpt-4",
    prompt: prompt  # ← Automatic linking
  ) do |gen|
    messages = prompt.compile(customer: "Alice")
    response = call_llm(messages)
    gen.output = response
  end
end

# OTel span attributes:
# {
#   "langfuse.type": "generation",
#   "langfuse.model": "gpt-4",
#   "langfuse.prompt_name": "support-assistant",    # Auto-captured
#   "langfuse.prompt_version": 3,                   # Auto-captured
#   "langfuse.input": "[{\"role\":\"system\"...}]"  # Compiled prompt
# }
```

### Implementation

```ruby
class Generation
  def initialize(otel_span, attributes = {})
    @otel_span = otel_span
    @attributes = attributes

    # Auto-detect prompt
    if attributes[:prompt].is_a?(Langfuse::TextPromptClient) ||
       attributes[:prompt].is_a?(Langfuse::ChatPromptClient)
      @otel_span.set_attribute("langfuse.prompt_name", attributes[:prompt].name)
      @otel_span.set_attribute("langfuse.prompt_version", attributes[:prompt].version)
    end
  end
end
```

---

## Cost & Token Tracking

### Automatic Cost Calculation (Same as Before)

```ruby
# Model pricing database (built-in)
LANGFUSE_MODEL_PRICING = {
  "gpt-4" => {
    prompt_tokens: 0.03 / 1000,
    completion_tokens: 0.06 / 1000
  },
  "gpt-4-turbo" => {
    prompt_tokens: 0.01 / 1000,
    completion_tokens: 0.03 / 1000
  }
  # ... more models
}
```

### Usage in Generation

```ruby
class Generation
  def usage=(usage_hash)
    model = @attributes[:model]

    # Set token counts as OTel attributes
    @otel_span.set_attribute("langfuse.usage.prompt_tokens", usage_hash[:prompt_tokens])
    @otel_span.set_attribute("langfuse.usage.completion_tokens", usage_hash[:completion_tokens])
    @otel_span.set_attribute("langfuse.usage.total_tokens", usage_hash[:total_tokens])

    # Auto-calculate cost if not provided
    unless usage_hash[:total_cost]
      cost = CostCalculator.calculate(
        model: model,
        prompt_tokens: usage_hash[:prompt_tokens],
        completion_tokens: usage_hash[:completion_tokens]
      )
      @otel_span.set_attribute("langfuse.usage.total_cost", cost)
    end
  end
end
```

---

## APM Integration

### How It Works

When multiple OTel exporters are configured, **the same trace appears in both Langfuse and your APM**:

```ruby
# config/initializers/opentelemetry.rb
OpenTelemetry::SDK.configure do |c|
  c.service_name = 'rails-app'

  # Langfuse exporter (LLM-specific details)
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      Langfuse::Exporter.new(...)
    )
  )

  # Datadog exporter (infrastructure details)
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new(
        endpoint: 'http://datadog-agent:4318'
      )
    )
  )
end
```

### Result in Datadog APM

```
Trace ID: abc123def456
├─ Span: chat-completion (Langfuse trace)
│  ├─ Duration: 3.2s
│  ├─ Service: rails-app
│  ├─ Attributes:
│  │  ├─ langfuse.user_id: "user-123"
│  │  └─ langfuse.session_id: "session-456"
│  │
│  ├─ Span: openai-call (Langfuse generation)
│  │  ├─ Duration: 2.8s
│  │  ├─ Attributes:
│  │  │  ├─ langfuse.model: "gpt-4"
│  │  │  ├─ langfuse.usage.total_tokens: 225
│  │  │  └─ langfuse.usage.total_cost: 0.00675
│  │
│  └─ Span: http.request (Datadog auto-instrumentation)
│     ├─ Duration: 2.7s
│     ├─ URL: https://api.openai.com/v1/chat/completions
│     └─ Status: 200
```

### Benefits

1. **Unified View**: See LLM calls alongside database queries, HTTP requests
2. **Performance Analysis**: Identify slow LLM calls impacting response time
3. **Error Correlation**: Link LLM failures to infrastructure issues
4. **Cost Attribution**: Correlate costs with specific users/features

---

## Error Handling & Resilience

### 1. Circuit Breaker (Same Pattern)

```ruby
class Langfuse::IngestionClient
  def initialize
    @circuit_breaker = Stoplight("langfuse-ingestion")
      .with_threshold(5)
      .with_timeout(30)
      .with_cool_off_time(10)
      .with_data_store(Stoplight::DataStore::Redis.new(Redis.current))
  end

  def send_batch(events)
    @circuit_breaker.run do
      connection.post("/api/public/ingestion", { batch: events })
    end
  rescue Stoplight::Error::RedLight => e
    Rails.logger.warn("Langfuse circuit open: #{e.message}")
    # Drop events or store for retry
  end
end
```

### 2. OTel Export Failures

```ruby
# If Langfuse exporter fails, OTel continues normally
class Langfuse::Exporter
  def export(span_data_list, timeout: nil)
    # Try to export
    events = convert_spans(span_data_list)
    send_events(events)

    OpenTelemetry::SDK::Trace::Export::SUCCESS
  rescue StandardError => e
    # Log but don't crash app
    Rails.logger.error("Langfuse export failed: #{e.message}")

    # Other exporters (Datadog) still work!
    OpenTelemetry::SDK::Trace::Export::FAILURE
  end
end
```

### 3. Graceful Degradation

```ruby
# Master kill switch
Langfuse.configure do |config|
  config.tracing_enabled = ENV.fetch("LANGFUSE_TRACING", "true") == "true"
end

# Disable exporter if tracing is off
def initialize_otel
  return unless Langfuse.config.tracing_enabled

  OpenTelemetry::SDK.configure do |c|
    c.add_span_processor(
      OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
        Langfuse::Exporter.new
      )
    )
  end
end
```

---

## Implementation Phases

### Phase T0: OpenTelemetry Setup (Week 1, Days 1-2)

**Goal:** Get OpenTelemetry working with basic tracing

#### T0.1 OTel Dependencies
- [ ] Add `opentelemetry-sdk` gem
- [ ] Add `opentelemetry-api` gem
- [ ] Add `opentelemetry-instrumentation-all` (optional)
- [ ] Add `opentelemetry-exporter-otlp` (optional, for APM)
- [ ] Update Gemfile and bundle install

#### T0.2 Basic OTel Configuration
- [ ] Create `config/initializers/opentelemetry.rb`
- [ ] Configure service name, version
- [ ] Add console exporter for testing
- [ ] Write basic trace/span test

#### T0.3 Verify OTel Works
- [ ] Create simple trace in test
- [ ] Verify spans are exported
- [ ] Test context propagation
- [ ] Document OTel setup

**Dependencies Added:**
- `opentelemetry-sdk ~> 1.4`
- `opentelemetry-api ~> 1.2`
- `opentelemetry-common ~> 0.21`
- `opentelemetry-exporter-otlp ~> 0.27` (optional)

**Milestone:** OTel tracing works!

---

### Phase T1: Langfuse Exporter (Week 1, Days 3-4)

**Goal:** Custom OTel exporter that converts spans to Langfuse events

#### T1.1 Exporter Skeleton
- [ ] Create `Langfuse::Exporter` class
- [ ] Implement `export(span_data_list)` method
- [ ] Implement `force_flush` and `shutdown`
- [ ] Register with OTel SpanProcessor

#### T1.2 Span Conversion
- [ ] Implement `convert_span_to_event(span)`
- [ ] Extract Langfuse attributes from OTel span
- [ ] Handle trace-create, span-create, generation-create
- [ ] Write conversion tests

#### T1.3 Ingestion Client (Sync)
- [ ] Create `Langfuse::IngestionClient`
- [ ] Implement `POST /api/public/ingestion`
- [ ] Add Basic Auth
- [ ] Add retry logic (Faraday)
- [ ] Write tests with WebMock

**Milestone:** OTel spans → Langfuse API!

---

### Phase T2: Ruby API Wrapper (Week 2)

**Goal:** Idiomatic Ruby API that wraps OTel

#### T2.1 Langfuse::Tracer
- [ ] Create wrapper around OTel tracer
- [ ] Implement `Langfuse.trace { |t| ... }`
- [ ] Map Ruby kwargs to OTel attributes
- [ ] Write tests

#### T2.2 Trace/Span/Generation Classes
- [ ] Create `Langfuse::Trace` wrapper
- [ ] Create `Langfuse::Span` wrapper
- [ ] Create `Langfuse::Generation` class
- [ ] Handle input/output/metadata
- [ ] Write comprehensive tests

#### T2.3 Global Configuration
- [ ] Add tracing config to `Langfuse::Config`
- [ ] Integrate with `Langfuse.configure`
- [ ] Auto-initialize OTel on configure
- [ ] Write tests

**Milestone:** Ruby block API works!

---

### Phase T3: Async Processing (Week 2-3)

**Goal:** Background processing via Sidekiq

#### T3.1 Event Buffer
- [ ] Create `Langfuse::EventBuffer`
- [ ] Implement thread-safe push/drain
- [ ] Add overflow handling
- [ ] Write concurrency tests

#### T3.2 Batch Span Processor
- [ ] Configure OTel BatchSpanProcessor
- [ ] Set batch size (50 spans)
- [ ] Set flush interval (10s)
- [ ] Test batching behavior

#### T3.3 Sidekiq Worker
- [ ] Create `Langfuse::IngestionWorker`
- [ ] Accept batch of events
- [ ] Send via IngestionClient
- [ ] Add error handling

#### T3.4 Async Configuration
- [ ] Add `tracing_async` config option
- [ ] Toggle between sync/async export
- [ ] Auto-detect Sidekiq availability
- [ ] Write tests

**Milestone:** Async batching works!

---

### Phase T4: Prompt Linking (Week 3)

**Goal:** Automatic prompt-to-trace linking

#### T4.1 Prompt Detection
- [ ] Detect `prompt:` kwarg in generation
- [ ] Extract name and version from PromptClient
- [ ] Add as OTel attributes

#### T4.2 OTel Attribute Mapping
- [ ] Add `langfuse.prompt_name` attribute
- [ ] Add `langfuse.prompt_version` attribute
- [ ] Include in exporter conversion

#### T4.3 Integration Tests
- [ ] Test end-to-end prompt linking
- [ ] Test with TextPromptClient
- [ ] Test with ChatPromptClient

**Milestone:** Automatic prompt linking!

---

### Phase T5: Cost Tracking (Week 3)

**Goal:** Automatic cost calculation

#### T5.1 Model Pricing Database
- [ ] Create pricing hash (same as before)
- [ ] Add OpenAI, Anthropic models
- [ ] Add custom pricing support

#### T5.2 Cost Calculator
- [ ] Create `Langfuse::CostCalculator`
- [ ] Calculate from tokens + model
- [ ] Handle unknown models

#### T5.3 Usage Enhancement
- [ ] Auto-calculate costs in `Generation#usage=`
- [ ] Add cost as OTel attribute
- [ ] Include in exporter

**Milestone:** Automatic cost calculation!

---

### Phase T6: Distributed Tracing (Week 4)

**Goal:** W3C Trace Context support

#### T6.1 Context Injection
- [ ] Implement `trace.inject_context`
- [ ] Use OTel propagation API
- [ ] Return W3C headers hash

#### T6.2 Context Extraction
- [ ] Implement `Langfuse.extract_context(headers)`
- [ ] Use OTel propagation API
- [ ] Link child traces to parent

#### T6.3 HTTP Instrumentation
- [ ] Add `opentelemetry-instrumentation-http`
- [ ] Test automatic header injection
- [ ] Test cross-service tracing

**Milestone:** Distributed tracing works!

---

### Phase T7: APM Integration (Week 4)

**Goal:** Multi-exporter configuration

#### T7.1 Multiple Exporters
- [ ] Document multi-exporter setup
- [ ] Test with Datadog + Langfuse
- [ ] Test with OTLP + Langfuse
- [ ] Ensure independent failures

#### T7.2 Correlation
- [ ] Verify trace IDs match across exporters
- [ ] Test unified traces in Datadog
- [ ] Document APM integration

**Milestone:** APM integration!

---

### Phase T8: Advanced Features (Week 5)

**Goal:** Events, scores, manual API

#### T8.1 Events
- [ ] Implement `trace.event(name, ...)`
- [ ] Use OTel span events
- [ ] Map to Langfuse event format
- [ ] Test event export

#### T8.2 Scores
- [ ] Implement `trace.score(name, value)`
- [ ] Buffer scores separately
- [ ] Send as score-create events
- [ ] Test score export

#### T8.3 Manual API
- [ ] Expose `trace.current_span` (OTel span)
- [ ] Support manual span start/end
- [ ] Document advanced usage

**Milestone:** Full feature parity!

---

### Phase T9: Rails Integration (Week 5)

**Goal:** Automatic Rails tracing

#### T9.1 Middleware
- [ ] Create `Langfuse::Middleware`
- [ ] Auto-wrap requests in traces
- [ ] Capture request metadata
- [ ] Use OTel Rack instrumentation

#### T9.2 ActiveJob Integration
- [ ] Auto-wrap jobs in traces
- [ ] Link job traces to request traces
- [ ] Use existing OTel ActiveJob instrumentation

**Milestone:** Automatic Rails tracing!

---

### Phase T10: Documentation & Polish (Week 6)

**Goal:** Production-ready release

#### T10.1 Documentation
- [ ] Complete API documentation (YARD)
- [ ] Write comprehensive README section
- [ ] Document OTel integration
- [ ] Write APM integration guide
- [ ] Document distributed tracing

#### T10.2 Performance Testing
- [ ] Benchmark OTel overhead
- [ ] Optimize exporter
- [ ] Memory profiling

#### T10.3 Final Polish
- [ ] Ensure >90% test coverage
- [ ] Fix all Rubocop issues
- [ ] Review error messages
- [ ] Final security review

**Milestone:** Tracing features ready for 1.0! 🚀

---

## Configuration Example

```ruby
# config/initializers/langfuse.rb
Langfuse.configure do |config|
  # Authentication
  config.public_key = ENV["LANGFUSE_PUBLIC_KEY"]
  config.secret_key = ENV["LANGFUSE_SECRET_KEY"]

  # Tracing
  config.tracing_enabled = true
  config.tracing_async = true
  config.batch_size = 50
  config.flush_interval = 10
  config.job_queue = :default  # ActiveJob queue name (default: :default)

  # Model pricing
  config.model_pricing["custom-model"] = {
    prompt_tokens: 0.005 / 1000,
    completion_tokens: 0.01 / 1000
  }
end

# config/initializers/opentelemetry.rb
OpenTelemetry::SDK.configure do |c|
  c.service_name = 'rails-app'
  c.service_version = ENV['APP_VERSION']

  # Langfuse exporter (LLM observability)
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      Langfuse::Exporter.new,
      max_queue_size: 1000,
      max_export_batch_size: 50,
      schedule_delay: 10_000  # 10 seconds
    )
  )

  # Optional: Datadog exporter (APM)
  if ENV['DD_AGENT_HOST']
    c.add_span_processor(
      OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
        OpenTelemetry::Exporter::OTLP::Exporter.new(
          endpoint: "http://#{ENV['DD_AGENT_HOST']}:4318"
        )
      )
    )
  end
end
```

---

## Dependencies

### Core OTel Dependencies
- `opentelemetry-sdk ~> 1.4` - Core tracing SDK
- `opentelemetry-api ~> 1.2` - Public API
- `opentelemetry-common ~> 0.21` - Common utilities

### Optional OTel Dependencies
- `opentelemetry-exporter-otlp ~> 0.27` - For APM integration
- `opentelemetry-instrumentation-http ~> 0.23` - Automatic HTTP tracing
- `opentelemetry-instrumentation-rails ~> 0.30` - Automatic Rails tracing
- `opentelemetry-instrumentation-active_job ~> 0.7` - ActiveJob tracing
- `opentelemetry-instrumentation-sidekiq ~> 0.25` - Sidekiq tracing

### Existing Dependencies (from prompt management)
- `faraday ~> 2.0` - HTTP client
- `faraday-retry ~> 2.0` - Retry logic

### New Dependencies (tracing-specific)
- `stoplight ~> 4.0` - Circuit breaker (if not added in prompt Phase 7)

---

## Open Questions

1. **OTel Instrumentation Scope**: Should we auto-install OTel instrumentations?
   - **Recommendation**: Make them optional, document in README

2. **Sampling Strategy**: Use OTel sampler or custom?
   - **Recommendation**: Use OTel ParentBasedSampler with configurable rate

3. **Score Timing**: When to send scores (immediate vs batched)?
   - **Recommendation**: Batch with other events for efficiency

4. **OTel Collector**: Support OTLP Collector as intermediary?
   - **Recommendation**: Yes, document as option for high-volume deployments

5. **Context Storage**: Use OTel Context API or custom?
   - **Recommendation**: Use OTel Context API (thread-safe, distributed-ready)

---

## Future Enhancements (Post-v1.0)

These features are not required for v1.0 but could be added in future releases based on user feedback:

### Automatic LLM Client Wrappers

**Motivation:** TypeScript and Python SDKs provide automatic wrappers for popular LLM clients (OpenAI, Anthropic) that eliminate boilerplate by auto-capturing inputs, outputs, and usage.

**TypeScript Example:**
```typescript
import { observeOpenAI } from '@langfuse/openai';
const openai = observeOpenAI(new OpenAI());

// All OpenAI calls automatically traced!
const completion = await openai.chat.completions.create({
  model: "gpt-4",
  messages: [{ role: "user", content: "Hello" }]
});
```

**Python Example:**
```python
from langfuse.openai import openai  # Wrapped client

# All calls automatically traced!
response = openai.chat.completions.create(
    model="gpt-4",
    messages=[{"role": "user", "content": "Hello"}]
)
```

**Proposed Ruby Implementation:**

```ruby
# gem install langfuse-openai (optional extension gem)
require 'langfuse/integrations/openai'

# Wrap OpenAI client for automatic tracing
openai = Langfuse::OpenAI.wrap(OpenAI::Client.new)

# Inside a Langfuse trace, OpenAI calls are auto-traced
Langfuse.trace(name: "user-query") do |trace|
  # Automatic generation span created!
  response = openai.chat(
    parameters: {
      model: "gpt-4",
      messages: [{ role: "user", content: "Hello" }]
    }
  )

  # Usage, tokens, cost automatically captured
  # Input/output automatically logged
  # Model name automatically detected
end
```

**Implementation Approach:**

1. **Separate Extension Gem** (optional dependency)
   - `langfuse-openai` gem for OpenAI integration
   - `langfuse-anthropic` gem for Anthropic integration
   - Keeps core `langfuse` gem lightweight

2. **Monkey-patching with Module Prepend**
   ```ruby
   module Langfuse
     module OpenAI
       def self.wrap(client)
         client.singleton_class.prepend(ClientExtensions)
         client
       end

       module ClientExtensions
         def chat(parameters:)
           # Extract trace context from OTel
           current_trace = Langfuse.current_trace

           if current_trace
             current_trace.generation(
               name: "openai-chat",
               model: parameters[:model],
               input: parameters[:messages]
             ) do |gen|
               response = super(parameters: parameters)

               gen.output = response.choices.first.message.content
               gen.usage = {
                 prompt_tokens: response.usage.prompt_tokens,
                 completion_tokens: response.usage.completion_tokens,
                 total_tokens: response.usage.total_tokens
               }

               response
             end
           else
             super(parameters: parameters)
           end
         end
       end
     end
   end
   ```

3. **OTel Context Detection**
   - Check if inside a Langfuse trace (via OTel context)
   - Only trace if within active trace
   - Pass through normally if not tracing

**Benefits:**
- ✅ Zero boilerplate for common use cases
- ✅ Matches TypeScript/Python SDK experience
- ✅ Automatic input/output/usage capture
- ✅ Optional (doesn't bloat core gem)

**Trade-offs:**
- ⚠️ Requires additional gem dependencies
- ⚠️ Monkey-patching risks (mitigated by Module#prepend)
- ⚠️ Needs maintenance for each LLM provider
- ⚠️ May not cover all edge cases

**Recommendation:** Implement as separate extension gems after v1.0, starting with `langfuse-openai` based on user demand.

---

## Success Metrics

After implementation, the SDK should achieve:

1. **Performance**: <2ms OTel overhead per trace/span creation
2. **Reliability**: >99.9% event delivery (with retry)
3. **Throughput**: Handle 10,000+ traces/second (async mode)
4. **Test Coverage**: >90% code coverage
5. **Memory**: <15MB memory overhead (OTel + Langfuse)
6. **Developer Experience**: <10 lines of code for typical use case
7. **APM Compatibility**: Works alongside Datadog, New Relic, etc.

---

## References

- [Langfuse Tracing Docs](https://langfuse.com/docs/tracing)
- [Langfuse Python SDK](https://langfuse.com/docs/sdk/python/low-level-sdk) (uses OTel)
- [OpenTelemetry Ruby](https://opentelemetry.io/docs/instrumentation/ruby/)
- [OpenTelemetry Specification](https://opentelemetry.io/docs/specs/otel/)
- [W3C Trace Context](https://www.w3.org/TR/trace-context/)
- [LaunchDarkly Ruby SDK](https://github.com/launchdarkly/ruby-server-sdk) (API inspiration)
- [Datadog OpenTelemetry](https://docs.datadoghq.com/tracing/setup_overview/open_standards/otel/)

---

## Key Advantages of OTel-Based Design

### vs Custom Implementation

| Feature | OTel-Based | Custom Implementation |
|---------|------------|----------------------|
| **Context Propagation** | Automatic (W3C Trace Context) | Manual thread-local storage |
| **Distributed Tracing** | Built-in across services | Complex custom solution |
| **APM Integration** | Native support | Requires custom exporters |
| **Industry Adoption** | CNCF standard, widely used | SDK-specific |
| **Code Maintenance** | Less custom code | More code to maintain |
| **Learning Curve** | OTel patterns (well-documented) | Custom patterns |
| **Instrumentation** | Rich ecosystem (auto-instrument) | Manual instrumentation |
| **Future-Proof** | Industry direction | May diverge from standards |

### Key Decision Points

**Choose OTel-Based Design If:**
- ✅ You want distributed tracing across microservices
- ✅ You use APM tools (Datadog, New Relic, Honeycomb)
- ✅ You want automatic instrumentation (HTTP, Rails, Sidekiq)
- ✅ You value industry standards over custom solutions
- ✅ You want unified observability (infrastructure + LLM)

**Avoid OTel If:**
- ❌ You need minimal dependencies (OTel adds ~10 gems)
- ❌ You only trace within a single app (no distributed tracing)
- ❌ You don't use APM tools
- ❌ You want complete control over internals

**For SimplePractice (100 microservices):** OTel-based design is **strongly recommended** due to distributed architecture and existing APM tooling.

---

**END OF DESIGN DOCUMENT**
