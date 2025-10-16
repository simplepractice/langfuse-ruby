# LLM Tracing Guide

Complete guide to tracing LLM applications with the Langfuse Ruby SDK.

## Table of Contents

- [Core Concepts](#core-concepts)
- [Quick Start](#quick-start)
- [Complete Examples](#complete-examples)
- [Best Practices](#best-practices)
- [Advanced Usage](#advanced-usage)

## Core Concepts

### Understanding Traces, Spans, Generations, and Events

| Concept | What It Is | When to Use | Has Duration? |
|---------|-----------|-------------|---------------|
| **Trace** | The entire journey of a request through your system | Top-level user request or operation | ✅ Yes |
| **Span** | A single unit of work within a trace | Any work that has a duration (retrieval, parsing, etc.) | ✅ Yes |
| **Generation** | A specialized span for LLM calls (Langfuse extension) | Calling an LLM (OpenAI, Anthropic, etc.) | ✅ Yes |
| **Event** | A point-in-time occurrence within a trace | Something happened at a point in time (log, feedback, flag) | ❌ No |

### Trace

The **entire journey** of a request through your system. It's the top-level container for all related work.

**Example:** A user asks a question → your app retrieves documents → calls an LLM → returns answer

**Properties:**
- **Trace ID**: Unique identifier that ties all the work together
- **Duration**: Total time from start to finish
- **Metadata**: user_id, session_id, tags, etc.

```ruby
Langfuse.trace(name: "user-question", user_id: "user-123", session_id: "session-456") do |trace|
  # Everything inside here is part of this trace
end
```

### Span

A **single unit of work** within a trace. Think of it as a function call or operation.

**Examples:**
- "Retrieve documents from vector DB"
- "Parse PDF file"
- "Call external API"
- "Database query"

**Properties:**
- Start/end timestamps (duration calculated automatically)
- Parent/child relationships (spans can be nested)
- Input/output data
- Metadata

```ruby
trace.span(name: "vector-search", input: { query: "What is Ruby?" }) do |span|
  results = vector_db.search(query, limit: 5)
  span.output = { count: results.size, ids: results.map(&:id) }
  span.metadata = { db_latency_ms: 42 }
  results
end
```

### Generation

A **specialized span for LLM calls**. This is NOT a standard OpenTelemetry concept - it's a Langfuse convention.

**Why separate from regular spans?**
- LLM calls have unique properties: model name, tokens, cost
- Need special handling for prompt tracking
- Want to aggregate LLM metrics separately

**Properties (in addition to span properties):**
- Model name and version
- Token usage (prompt, completion, total)
- Model parameters (temperature, max_tokens, etc.)
- Prompt information (if using Langfuse prompts)

```ruby
trace.generation(
  name: "gpt4-call",
  model: "gpt-4",
  input: [{ role: "user", content: "Hello" }],
  model_parameters: { temperature: 0.7, max_tokens: 500 }
) do |gen|
  response = openai_client.chat(...)

  gen.output = response.choices.first.message.content
  gen.usage = {
    prompt_tokens: 10,
    completion_tokens: 20,
    total_tokens: 30
  }
end
```

**Under the hood:** A generation is still a span in OpenTelemetry, but with additional LLM-specific attributes that Langfuse understands.

### Event

A **point-in-time occurrence** within a span or trace. Like a log message but structured.

**Examples:**
- "Cache hit"
- "User provided feedback"
- "Rate limit encountered"
- "Retry attempt"

**Properties:**
- Timestamp (automatically captured)
- Name
- Input/output data
- Metadata

```ruby
# Event on a trace
trace.event(name: "user-feedback", input: { rating: "thumbs_up", comment: "Very helpful!" })

# Event on a span
span.event(name: "cache-hit", metadata: { key: "prompt-greeting-v2" })
```

**Key difference from spans:**
- Events have NO duration (just a timestamp)
- Events don't have children
- Think "something happened" vs. "doing work"

## Quick Start

### Basic Trace with Generation

```ruby
Langfuse.trace(name: "chat-completion", user_id: "user-123") do |trace|
  trace.generation(
    name: "openai-call",
    model: "gpt-4",
    input: [{ role: "user", content: "Hello, how are you?" }]
  ) do |gen|
    response = openai_client.chat(
      parameters: {
        model: "gpt-4",
        messages: [{ role: "user", content: "Hello, how are you?" }]
      }
    )

    gen.output = response.choices.first.message.content
    gen.usage = {
      prompt_tokens: response.usage.prompt_tokens,
      completion_tokens: response.usage.completion_tokens,
      total_tokens: response.usage.total_tokens
    }
  end
end
```

### Nested Spans

```ruby
Langfuse.trace(name: "document-processing") do |trace|
  # Parent span
  trace.span(name: "pdf-extraction") do |parent|
    # Child span
    parent.span(name: "parse-pages") do |child|
      pages = extract_pages(pdf_file)
      child.output = { page_count: pages.size }
    end

    # Another child span
    parent.span(name: "extract-text") do |child|
      text = extract_text(pages)
      child.output = { text_length: text.length }
    end
  end
end
```

## Complete Examples

### RAG Pipeline with Full Instrumentation

```ruby
def answer_question(user_id:, question:)
  Langfuse.trace(
    name: "qa-request",
    user_id: user_id,
    metadata: { question: question, source: "web" }
  ) do |trace|

    # Step 1: Retrieve relevant documents
    documents = trace.span(name: "document-retrieval", input: { query: question }) do |span|
      # Generate embedding for question
      embedding = span.generation(
        name: "embed-question",
        model: "text-embedding-ada-002",
        input: question
      ) do |gen|
        result = openai_client.embeddings(
          parameters: { model: "text-embedding-ada-002", input: question }
        )
        gen.output = result.data.first.embedding
        gen.usage = { total_tokens: result.usage.total_tokens }
        result.data.first.embedding
      end

      # Search vector database
      docs = vector_db.similarity_search(embedding, limit: 3)
      span.output = { doc_ids: docs.map(&:id), count: docs.size }
      span.metadata = { search_latency_ms: 45 }
      docs
    end

    # Step 2: Generate answer with LLM
    prompt = Langfuse.client.get_prompt("qa-with-context", label: "production")

    answer = trace.generation(
      name: "generate-answer",
      model: "gpt-4",
      prompt: prompt,  # Automatically links to Langfuse prompt
      model_parameters: { temperature: 0.3, max_tokens: 500 }
    ) do |gen|
      messages = prompt.compile(
        question: question,
        context: documents.map(&:content).join("\n\n")
      )

      response = openai_client.chat(
        parameters: {
          model: "gpt-4",
          messages: messages,
          temperature: 0.3,
          max_tokens: 500
        }
      )

      gen.output = response.choices.first.message.content
      gen.usage = {
        prompt_tokens: response.usage.prompt_tokens,
        completion_tokens: response.usage.completion_tokens,
        total_tokens: response.usage.total_tokens
      }

      response.choices.first.message.content
    end

    # Step 3: Log result event
    trace.event(
      name: "answer-generated",
      input: { question: question },
      output: { answer: answer, sources: documents.map(&:id) }
    )

    answer
  end
end
```

**Visual representation:**
```
Trace: qa-request (2.8s total)
│
├─ Span: document-retrieval (0.8s)
│  ├─ Generation: embed-question (0.3s)
│  └─ (vector search happens here)
│
├─ Generation: generate-answer (2.0s)
│
└─ Event: answer-generated (instant)
```

### Multi-Turn Conversation

```ruby
def chat_conversation(user_id:, session_id:, messages:)
  Langfuse.trace(
    name: "conversation",
    user_id: user_id,
    session_id: session_id
  ) do |trace|

    # Load conversation history
    history = trace.span(name: "load-history") do |span|
      history = conversation_store.get(session_id)
      span.output = { message_count: history.size }
      history
    end

    # Get system prompt
    prompt = Langfuse.client.get_prompt("chat-system", label: "production")
    system_message = prompt.compile(user_name: get_user_name(user_id))

    # Generate response
    response = trace.generation(
      name: "chat-completion",
      model: "gpt-4",
      prompt: prompt,
      input: [system_message] + history + messages
    ) do |gen|
      result = openai_client.chat(
        parameters: {
          model: "gpt-4",
          messages: [system_message] + history + messages
        }
      )

      gen.output = result.choices.first.message.content
      gen.usage = {
        prompt_tokens: result.usage.prompt_tokens,
        completion_tokens: result.usage.completion_tokens
      }

      result.choices.first.message.content
    end

    # Save to history
    trace.span(name: "save-history") do |span|
      conversation_store.append(session_id, messages + [{ role: "assistant", content: response }])
      span.output = { saved: true }
    end

    response
  end
end
```

### Error Handling and Retry Tracking

```ruby
def call_llm_with_retry(prompt:, max_retries: 3)
  Langfuse.trace(name: "llm-with-retry") do |trace|
    attempt = 0

    trace.generation(name: "openai-call", model: "gpt-4", input: prompt) do |gen|
      begin
        attempt += 1
        trace.event(name: "attempt", metadata: { attempt_number: attempt })

        response = openai_client.chat(
          parameters: { model: "gpt-4", messages: prompt }
        )

        gen.output = response.choices.first.message.content
        gen.usage = {
          prompt_tokens: response.usage.prompt_tokens,
          completion_tokens: response.usage.completion_tokens
        }

        response.choices.first.message.content
      rescue OpenAI::RateLimitError => e
        trace.event(name: "rate-limit", metadata: { attempt: attempt, error: e.message })

        if attempt < max_retries
          sleep(2 ** attempt)  # Exponential backoff
          retry
        else
          gen.level = "error"
          gen.metadata = { error: "max_retries_exceeded", attempts: attempt }
          raise
        end
      rescue => e
        gen.level = "error"
        gen.metadata = { error_class: e.class.name, error_message: e.message }
        raise
      end
    end
  end
end
```

## Best Practices

### 1. Always Capture Usage Information

```ruby
# ✅ Good - captures token usage
trace.generation(name: "gpt4", model: "gpt-4", input: messages) do |gen|
  response = openai_client.chat(...)
  gen.output = response.choices.first.message.content
  gen.usage = {
    prompt_tokens: response.usage.prompt_tokens,
    completion_tokens: response.usage.completion_tokens,
    total_tokens: response.usage.total_tokens
  }
end

# ❌ Bad - missing usage information
trace.generation(name: "gpt4", model: "gpt-4", input: messages) do |gen|
  response = openai_client.chat(...)
  gen.output = response.choices.first.message.content
  # Missing: gen.usage = ...
end
```

### 2. Use Descriptive Names

```ruby
# ✅ Good - clear what this does
trace.span(name: "retrieve-user-documents")

# ❌ Bad - too generic
trace.span(name: "process")
```

### 3. Add Metadata for Context

```ruby
# ✅ Good - includes useful context
trace.span(name: "database-query") do |span|
  results = db.query(sql)
  span.output = { count: results.size }
  span.metadata = {
    query_time_ms: elapsed_time,
    rows_scanned: results.meta.rows_scanned,
    cache_hit: false
  }
end
```

### 4. Link Prompts to Generations

```ruby
# ✅ Good - automatic prompt tracking
prompt = Langfuse.client.get_prompt("greeting", version: 2)
trace.generation(name: "greet", model: "gpt-4", prompt: prompt) do |gen|
  # Langfuse will automatically link this generation to the prompt
end

# ❌ Less useful - no prompt tracking
trace.generation(name: "greet", model: "gpt-4") do |gen|
  # Which prompt was used? What version?
end
```

### 5. Use Events for Important Milestones

```ruby
Langfuse.trace(name: "user-onboarding") do |trace|
  trace.event(name: "started", input: { source: "mobile_app" })

  # ... do work ...

  trace.event(name: "completed", metadata: { duration_minutes: 5 })
  trace.event(name: "user-feedback", input: { rating: 5 })
end
```

### 6. Set Error Levels Appropriately

```ruby
trace.span(name: "api-call") do |span|
  begin
    result = external_api.call
    span.output = result
  rescue RateLimitError => e
    span.level = "warning"  # Recoverable error
    span.metadata = { error: e.message, retry_after: 60 }
  rescue => e
    span.level = "error"  # Unexpected error
    span.metadata = { error_class: e.class.name, error: e.message }
    raise
  end
end
```

## Advanced Usage

### Distributed Tracing Across Services

```ruby
# Service A (API Gateway)
def handle_request
  Langfuse.trace(name: "api-request", user_id: "user-123") do |trace|
    # Inject trace context into HTTP headers
    headers = trace.inject_context

    # Call downstream service with trace context
    response = HTTParty.post(
      "http://service-b/process",
      headers: headers,
      body: { query: "..." }
    )
  end
end

# Service B (Processing Service)
def process_request(request)
  # Extract context from incoming headers
  context = Langfuse.extract_context(request.headers)

  # This trace is automatically linked to the parent trace!
  Langfuse.trace(name: "process-data", context: context) do |trace|
    trace.generation(name: "llm-call", model: "gpt-4") do |gen|
      # ... LLM processing
    end
  end
end
```

### Custom Observability Levels

```ruby
Langfuse.trace(name: "production-query") do |trace|
  # Debug-level span (only in development/staging)
  trace.span(name: "cache-check") do |span|
    span.level = "debug"
    # ... cache logic
  end

  # Default-level generation (always tracked)
  trace.generation(name: "llm-call", model: "gpt-4") do |gen|
    span.level = "default"
    # ... LLM call
  end

  # Warning-level event (important but not error)
  if cache_miss_rate > 0.8
    trace.event(name: "high-cache-miss-rate", metadata: { rate: cache_miss_rate })
    trace.level = "warning"
  end
end
```

### Background Jobs and Async Processing

```ruby
# Enqueue job with trace context
class ProcessDocumentJob < ApplicationJob
  def perform(document_id, trace_context = nil)
    # Continue trace from web request
    Langfuse.trace(name: "process-document", context: trace_context) do |trace|
      trace.span(name: "extract-text") do |span|
        text = extract_text(document_id)
        span.output = { text_length: text.length }
      end

      trace.generation(name: "summarize", model: "gpt-4") do |gen|
        summary = generate_summary(text)
        gen.output = summary
      end
    end
  end
end

# In controller - pass trace context to job
Langfuse.trace(name: "document-upload") do |trace|
  document = Document.create!(params)

  # Extract context to pass to background job
  context = trace.extract_context
  ProcessDocumentJob.perform_later(document.id, context)

  trace.event(name: "job-enqueued", metadata: { document_id: document.id })
end
```

## OpenTelemetry Integration

The SDK is built on OpenTelemetry, which provides:

### Automatic Context Propagation

Trace context automatically flows through:
- HTTP requests (via headers)
- Background jobs (if properly configured)
- Database queries (with OTel instrumentation)
- Redis operations (with OTel instrumentation)

### APM Integration

Traces can be exported to multiple observability platforms:

```ruby
# config/initializers/opentelemetry.rb
require 'opentelemetry/sdk'
require 'langfuse/otel_setup'

Langfuse::OtelSetup.configure do |config|
  config.service_name = 'my-rails-app'
  config.service_version = ENV['APP_VERSION']

  # Add additional exporters
  config.add_exporter(:datadog)
  config.add_exporter(:honeycomb)
end
```

Your traces will appear in:
- Langfuse (for LLM-specific analytics)
- Datadog APM
- New Relic
- Honeycomb
- Any OpenTelemetry-compatible platform

### W3C Trace Context

The SDK uses the [W3C Trace Context](https://www.w3.org/TR/trace-context/) standard for distributed tracing:

```
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
```

This allows traces to flow seamlessly across:
- Ruby services
- Node.js services
- Python services
- Go services
- Any service that implements W3C Trace Context

## Resources

- [Langfuse Documentation](https://langfuse.com/docs)
- [OpenTelemetry Ruby Documentation](https://opentelemetry.io/docs/instrumentation/ruby/)
- [W3C Trace Context Specification](https://www.w3.org/TR/trace-context/)
