# Langfuse Ruby SDK

Official Ruby SDK for [Langfuse](https://langfuse.com) - Open-source LLM observability and prompt management.

[![Gem Version](https://badge.fury.io/rb/langfuse.svg)](https://badge.fury.io/rb/langfuse)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.2.0-ruby.svg)](https://www.ruby-lang.org/en/)
[![Test Coverage](https://img.shields.io/badge/coverage-99.6%25-brightgreen.svg)](coverage)

## Features

- ✅ **Prompt Management** - Fetch and compile prompts with variable substitution
- ✅ **LLM Tracing & Observability** - Built on OpenTelemetry for distributed tracing
- ✅ **In-Memory Caching** - Thread-safe caching with TTL and LRU eviction
- ✅ **Text & Chat Prompts** - Support for both simple text and chat/completion prompts
- ✅ **Mustache Templating** - Logic-less variable substitution
- ✅ **Rails-Friendly** - Global configuration pattern with `Langfuse.configure`
- ✅ **Thread-Safe** - Safe for multi-threaded environments
- ✅ **APM Integration** - Works with Datadog, New Relic, Honeycomb, etc.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'langfuse'
```

And then execute:

```bash
bundle install
```

Or install it yourself:

```bash
gem install langfuse
```

## Quick Start

### Global Configuration (Recommended for Rails)

```ruby
# config/initializers/langfuse.rb
Langfuse.configure do |config|
  config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
  config.secret_key = ENV['LANGFUSE_SECRET_KEY']
  config.base_url = "https://cloud.langfuse.com"  # Optional, this is the default
  config.cache_ttl = 60  # Optional: cache prompts for 60 seconds
end

# Then use the global singleton client anywhere in your app
client = Langfuse.client
prompt = client.get_prompt("greeting")
text = prompt.compile(name: "Alice")
puts text  # => "Hello Alice!"
```

### Instance-Based Configuration

```ruby
# Create a custom configuration
config = Langfuse::Config.new do |c|
  c.public_key = "pk_..."
  c.secret_key = "sk_..."
  c.cache_ttl = 120
end

# Create a client with this configuration
client = Langfuse::Client.new(config)
prompt = client.get_prompt("greeting")
```

## Usage Examples

### Text Prompts

Text prompts are simple string templates with Mustache-style variables:

```ruby
# Fetch a text prompt
prompt = Langfuse.client.get_prompt("email-template")

# Access metadata
puts prompt.name        # => "email-template"
puts prompt.version     # => 3
puts prompt.labels      # => ["production"]
puts prompt.tags        # => ["email", "customer"]

# The raw template stored in Langfuse looks like this:
puts prompt.prompt
# => "Dear {{customer_name}}, your order #{{order_number}} for {{total}} has shipped!"

# Compile with variables to populate the template
email = prompt.compile(
  customer_name: "Alice",
  order_number: "12345",
  total: "$99.99"
)
puts email
# => "Dear Alice, your order #12345 for $99.99 has shipped!"
```

**Template in Langfuse:**
```
Dear {{customer_name}}, your order #{{order_number}} for {{total}} has shipped!
```

**After compilation:**
```
Dear Alice, your order #12345 for $99.99 has shipped!
```

### Chat Prompts

Chat prompts return arrays of messages for LLM APIs (OpenAI, Anthropic, etc.):

```ruby
# Fetch a chat prompt
prompt = Langfuse.client.get_prompt("support-assistant")

# The raw template stored in Langfuse looks like this:
puts prompt.prompt
# => [
#      { "role" => "system", "content" => "You are a {{support_level}} support agent for {{company_name}}." },
#      { "role" => "user", "content" => "How can I help you today?" }
#    ]

# Compile with variables to populate the template
messages = prompt.compile(
  company_name: "Acme Corp",
  support_level: "premium"
)

# Result is ready to use with OpenAI, Anthropic, etc.
puts messages
# => [
#      { role: :system, content: "You are a premium support agent for Acme Corp." },
#      { role: :user, content: "How can I help you today?" }
#    ]

# Use directly with OpenAI
require 'openai'
client = OpenAI::Client.new
response = client.chat(
  parameters: {
    model: "gpt-4",
    messages: messages  # Ready to use!
  }
)
```

**Template in Langfuse:**
```json
[
  {
    "role": "system",
    "content": "You are a {{support_level}} support agent for {{company_name}}."
  },
  {
    "role": "user",
    "content": "How can I help you today?"
  }
]
```

**After compilation:**
```ruby
[
  { role: :system, content: "You are a premium support agent for Acme Corp." },
  { role: :user, content: "How can I help you today?" }
]
```

### Prompt Versioning

```ruby
# Fetch a specific version
prompt_v1 = Langfuse.client.get_prompt("greeting", version: 1)
prompt_v2 = Langfuse.client.get_prompt("greeting", version: 2)

# Or fetch by label
production_prompt = Langfuse.client.get_prompt("greeting", label: "production")
staging_prompt = Langfuse.client.get_prompt("greeting", label: "staging")
```

### Advanced Variable Substitution

The SDK uses Mustache for powerful, logic-less templating:

#### Nested Objects

**Template in Langfuse:**
```
Hello {{user.name}}, we'll email you at {{user.email}}
```

**Ruby code:**
```ruby
prompt.compile(
  user: {
    name: "Alice",
    email: "alice@example.com"
  }
)
```

**Result:**
```
Hello Alice, we'll email you at alice@example.com
```

#### Lists/Arrays

**Template in Langfuse:**
```
{{#items}}• {{name}}: ${{price}}
{{/items}}
```

**Ruby code:**
```ruby
prompt.compile(
  items: [
    { name: "Apple", price: 1.99 },
    { name: "Banana", price: 0.99 }
  ]
)
```

**Result:**
```
• Apple: $1.99
• Banana: $0.99
```

#### HTML Escaping

**Template in Langfuse:**
```
User input: {{content}}
```

**Ruby code:**
```ruby
prompt.compile(content: "<script>alert('xss')</script>")
```

**Result (automatic escaping):**
```
User input: &lt;script&gt;alert('xss')&lt;/script&gt;
```

#### Raw/Unescaped Output

**Template in Langfuse:**
```
{{{raw_html}}}
```

**Ruby code:**
```ruby
prompt.compile(raw_html: "<strong>Bold</strong>")
```

**Result (no escaping with triple braces):**
```
<strong>Bold</strong>
```

## LLM Tracing & Observability

The SDK provides comprehensive LLM tracing built on **OpenTelemetry**, the CNCF standard for distributed tracing. Traces capture LLM calls, nested operations, token usage, and costs, giving you complete visibility into your LLM application.

### Basic Trace with Generation

```ruby
# Trace a single LLM call
Langfuse.trace(name: "chat-completion", user_id: "user-123") do |trace|
  trace.generation(
    name: "openai-call",
    model: "gpt-4",
    input: [{ role: "user", content: "Hello, how are you?" }]
  ) do |gen|
    # Call your LLM
    response = openai_client.chat(
      parameters: {
        model: "gpt-4",
        messages: [{ role: "user", content: "Hello, how are you?" }]
      }
    )

    # Capture output and usage
    gen.output = response.choices.first.message.content
    gen.usage = {
      prompt_tokens: response.usage.prompt_tokens,
      completion_tokens: response.usage.completion_tokens,
      total_tokens: response.usage.total_tokens
    }
  end
end
```

### Nested Spans (RAG Pipeline Example)

```ruby
Langfuse.trace(name: "rag-query", user_id: "user-456", session_id: "session-789") do |trace|
  # Document retrieval span
  docs = trace.span(name: "retrieval", input: { query: "What is Ruby?" }) do |span|
    # Generate embedding
    embedding = span.generation(
      name: "embed-query",
      model: "text-embedding-ada-002",
      input: "What is Ruby?"
    ) do |gen|
      result = openai_client.embeddings(
        parameters: { model: "text-embedding-ada-002", input: "What is Ruby?" }
      )
      gen.output = result.data.first.embedding
      gen.usage = { total_tokens: result.usage.total_tokens }
      result.data.first.embedding
    end

    # Search vector database
    results = vector_db.search(embedding, limit: 5)
    span.output = { results: results, count: results.size }
    span.metadata = { latency_ms: 42 }
    results
  end

  # LLM generation with retrieved context
  trace.generation(
    name: "gpt4-completion",
    model: "gpt-4",
    input: build_prompt_with_context(docs),
    model_parameters: { temperature: 0.7 }
  ) do |gen|
    response = openai_client.chat(...)
    gen.output = response.choices.first.message.content
    gen.usage = {
      prompt_tokens: response.usage.prompt_tokens,
      completion_tokens: response.usage.completion_tokens,
      total_tokens: response.usage.total_tokens
    }
  end

  # Track user feedback
  trace.event(name: "user-feedback", input: { rating: "thumbs_up" })
end
```

### Automatic Prompt Linking

When using prompts from the SDK, they're automatically linked to your traces:

```ruby
# Fetch a prompt
prompt = Langfuse.client.get_prompt("support-assistant", version: 3)

Langfuse.trace(name: "support-query") do |trace|
  trace.generation(
    name: "response",
    model: "gpt-4",
    prompt: prompt  # ← Automatically captured!
  ) do |gen|
    # Compile prompt with variables
    messages = prompt.compile(customer_name: "Alice", issue: "login problem")

    response = openai_client.chat(parameters: { model: "gpt-4", messages: messages })
    gen.output = response.choices.first.message.content
    gen.usage = {
      prompt_tokens: response.usage.prompt_tokens,
      completion_tokens: response.usage.completion_tokens,
      total_tokens: response.usage.total_tokens
    }
  end
end

# The trace will show:
# - prompt_name: "support-assistant"
# - prompt_version: 3
# - input: [compiled messages]
```

### Spans and Metadata

Track any operation as a span with custom metadata:

```ruby
Langfuse.trace(name: "document-processing") do |trace|
  trace.span(name: "pdf-parsing", input: { file: "report.pdf" }) do |span|
    parsed_data = parse_pdf("report.pdf")
    span.output = { pages: parsed_data.pages, text_length: parsed_data.text.length }
    span.metadata = { file_size_mb: 2.5, parse_time_ms: 150 }
  end

  trace.span(name: "text-analysis") do |span|
    span.metadata = { model: "custom-analyzer", version: "1.2" }
    # ... analysis logic
  end
end
```

### Events

Add point-in-time events to traces:

```ruby
Langfuse.trace(name: "user-conversation") do |trace|
  # User starts conversation
  trace.event(name: "conversation-started", input: { channel: "web" })

  # LLM generation
  trace.generation(name: "response", model: "gpt-4") do |gen|
    # ... LLM call
  end

  # User provides feedback
  trace.event(name: "user-feedback", input: { rating: "thumbs_up", comment: "Very helpful!" })
end
```

### Observability Levels

Control the visibility of traces with levels:

```ruby
Langfuse.trace(name: "production-query") do |trace|
  trace.span(name: "database-query") do |span|
    span.level = "debug"  # Options: debug, default, warning, error
    # ...
  end

  trace.generation(name: "llm-call", model: "gpt-4") do |gen|
    begin
      # ... LLM call
    rescue => e
      gen.level = "error"
      raise
    end
  end
end
```

### Distributed Tracing

The SDK supports distributed tracing across microservices using W3C Trace Context:

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

### OpenTelemetry Integration

The SDK is built on OpenTelemetry, which means:

- **Automatic Context Propagation**: Trace context flows automatically through your application
- **APM Integration**: Traces appear in Datadog, New Relic, Honeycomb, etc.
- **Rich Instrumentation**: Works with existing OTel instrumentation (HTTP, Rails, Sidekiq)
- **Industry Standard**: Uses W3C Trace Context for distributed tracing

To enable OpenTelemetry setup:

```ruby
# config/initializers/opentelemetry.rb
require 'opentelemetry/sdk'
require 'langfuse/otel_setup'

# Initialize OpenTelemetry with Langfuse
Langfuse::OtelSetup.configure do |config|
  config.service_name = 'my-rails-app'
  config.service_version = ENV['APP_VERSION']
end
```

### Complete Example: Q&A with RAG

```ruby
def answer_question(user_id:, question:)
  Langfuse.trace(name: "qa-request", user_id: user_id, metadata: { question: question }) do |trace|
    # Step 1: Retrieve relevant documents
    documents = trace.span(name: "document-retrieval", input: { query: question }) do |span|
      # Generate embedding for question
      embedding = span.generation(
        name: "embed-question",
        model: "text-embedding-ada-002",
        input: question
      ) do |gen|
        result = generate_embedding(question)
        gen.output = result[:embedding]
        gen.usage = { total_tokens: result[:tokens] }
        result[:embedding]
      end

      # Search vector database
      docs = vector_db.similarity_search(embedding, limit: 3)
      span.output = { doc_ids: docs.map(&:id), count: docs.size }
      docs
    end

    # Step 2: Generate answer with LLM
    prompt = Langfuse.client.get_prompt("qa-with-context", label: "production")

    answer = trace.generation(
      name: "generate-answer",
      model: "gpt-4",
      prompt: prompt,
      model_parameters: { temperature: 0.3, max_tokens: 500 }
    ) do |gen|
      messages = prompt.compile(
        question: question,
        context: documents.map(&:content).join("\n\n")
      )

      response = openai_client.chat(
        parameters: { model: "gpt-4", messages: messages, temperature: 0.3 }
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

## Configuration Options

```ruby
Langfuse.configure do |config|
  # Required: Authentication
  config.public_key = "pk_..."      # Your Langfuse public key
  config.secret_key = "sk_..."      # Your Langfuse secret key

  # Optional: API Settings
  config.base_url = "https://cloud.langfuse.com"  # Default
  config.timeout = 5                # Request timeout in seconds (default: 5)

  # Optional: Caching
  config.cache_ttl = 60             # Cache prompts for 60 seconds (default: 60)
  config.cache_max_size = 1000      # Max cached prompts (default: 1000)
  # Set cache_ttl to 0 to disable caching

  # Optional: Logging
  config.logger = Rails.logger      # Custom logger (default: Logger.new($stdout))
end
```

### Environment Variables

You can also configure using environment variables:

```bash
export LANGFUSE_PUBLIC_KEY="pk_..."
export LANGFUSE_SECRET_KEY="sk_..."
export LANGFUSE_BASE_URL="https://cloud.langfuse.com"
```

```ruby
# Config will automatically read from ENV
Langfuse.configure do |config|
  # Keys are automatically loaded from ENV if not set
end
```

## Caching

The SDK includes built-in thread-safe caching with TTL and LRU eviction:

```ruby
# Enable caching (recommended for production)
Langfuse.configure do |config|
  config.public_key = "pk_..."
  config.secret_key = "sk_..."
  config.cache_ttl = 300        # Cache for 5 minutes
  config.cache_max_size = 500   # Store up to 500 prompts
end

# First call hits the API
prompt1 = Langfuse.client.get_prompt("greeting")  # API call

# Second call uses cache (within TTL)
prompt2 = Langfuse.client.get_prompt("greeting")  # Cached!

# Different versions are cached separately
v1 = Langfuse.client.get_prompt("greeting", version: 1)  # API call
v2 = Langfuse.client.get_prompt("greeting", version: 2)  # API call
v1_cached = Langfuse.client.get_prompt("greeting", version: 1)  # Cached!

# Disable caching if needed
Langfuse.configure do |config|
  config.cache_ttl = 0  # Disables caching
end
```

**Cache Features:**
- Thread-safe with Monitor-based synchronization
- TTL-based expiration (configurable)
- LRU eviction when max_size is reached
- Separate cache keys for name, version, and label combinations

## Error Handling

```ruby
begin
  prompt = Langfuse.client.get_prompt("my-prompt")
rescue Langfuse::NotFoundError => e
  # Prompt doesn't exist
  puts "Prompt not found: #{e.message}"
rescue Langfuse::UnauthorizedError => e
  # Invalid API keys
  puts "Authentication failed: #{e.message}"
rescue Langfuse::ApiError => e
  # Other API errors (500, network issues, etc.)
  puts "API error: #{e.message}"
end
```

**Exception Hierarchy:**
```
StandardError
└── Langfuse::Error
    ├── Langfuse::ConfigurationError  # Invalid configuration
    └── Langfuse::ApiError             # API request failed
        ├── Langfuse::NotFoundError    # 404 - Prompt not found
        └── Langfuse::UnauthorizedError # 401 - Bad credentials
```

## API Reference

### `Langfuse.configure`

Configure the SDK globally. Typically called in a Rails initializer.

```ruby
Langfuse.configure do |config|
  config.public_key = "pk_..."
  config.secret_key = "sk_..."
  # ... other options
end
```

### `Langfuse.client`

Returns the global singleton client instance.

```ruby
client = Langfuse.client
```

### `Langfuse.reset!`

Resets global configuration and client. Useful for testing.

```ruby
Langfuse.reset!
```

### `Client#get_prompt(name, version: nil, label: nil)`

Fetches a prompt and returns a `TextPromptClient` or `ChatPromptClient`.

**Parameters:**
- `name` (String, required): The prompt name
- `version` (Integer, optional): Specific version number
- `label` (String, optional): Label like "production" or "staging"

**Returns:** `TextPromptClient` or `ChatPromptClient`

**Raises:** `ArgumentError` if both version and label are provided

```ruby
# Fetch latest version
prompt = client.get_prompt("greeting")

# Fetch specific version
prompt = client.get_prompt("greeting", version: 2)

# Fetch by label
prompt = client.get_prompt("greeting", label: "production")
```

### `TextPromptClient#compile(variables = {})`

Compiles a text prompt with variable substitution.

**Parameters:**
- `variables` (Hash, optional): Variables to substitute

**Returns:** String

```ruby
prompt = client.get_prompt("welcome-email")
text = prompt.compile(name: "Alice", date: "Jan 1")
```

### `ChatPromptClient#compile(variables = {})`

Compiles a chat prompt with variable substitution.

**Parameters:**
- `variables` (Hash, optional): Variables to substitute

**Returns:** Array of message hashes with `:role` and `:content`

```ruby
prompt = client.get_prompt("support-bot")
messages = prompt.compile(company: "Acme")
# => [{ role: :system, content: "..." }, { role: :user, content: "..." }]
```

### Prompt Client Properties

Both `TextPromptClient` and `ChatPromptClient` expose:

```ruby
prompt.name        # String - Prompt name
prompt.version     # Integer - Version number
prompt.prompt      # String or Array - The raw prompt template
prompt.labels      # Array - Labels like ["production"]
prompt.tags        # Array - Tags for organization
prompt.config      # Hash - Additional configuration from Langfuse
```

## Testing

The SDK is designed to be test-friendly:

```ruby
# In your test setup
RSpec.configure do |config|
  config.before(:each) do
    Langfuse.reset!  # Clear global state
  end
end

# Mock prompts in tests
before do
  allow_any_instance_of(Langfuse::Client)
    .to receive(:get_prompt)
    .with("greeting")
    .and_return(
      Langfuse::TextPromptClient.new(
        "name" => "greeting",
        "version" => 1,
        "type" => "text",
        "prompt" => "Hello {{name}}!",
        "labels" => [],
        "tags" => [],
        "config" => {}
      )
    )
end
```

## Requirements

- Ruby >= 3.2.0
- No Rails dependency (works with any Ruby project)

## Thread Safety

All components are thread-safe:
- `Langfuse.configure` and `Langfuse.client` are safe to call from multiple threads
- `PromptCache` uses Monitor-based synchronization
- `Client` instances can be shared across threads

## Development

```bash
# Clone the repository
git clone https://github.com/langfuse/langfuse-ruby.git
cd langfuse-ruby

# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run tests with coverage
bundle exec rspec
# Open coverage/index.html

# Run linter
bundle exec rubocop

# Auto-fix linting issues
bundle exec rubocop -a
```

## Architecture

The gem follows a clean, modular architecture inspired by LaunchDarkly:

- **Flat API**: All methods on `Client`, no nested managers
- **Global Config**: Rails-friendly `Langfuse.configure` pattern
- **Thread-Safe**: Monitor-based synchronization for caching
- **Minimal Dependencies**: Only Faraday (HTTP) and Mustache (templating)
- **Test-Driven**: 99.6% test coverage with 187 test cases

**Components:**
```
Langfuse (global module)
└── Client (main entry point)
    ├── ApiClient (HTTP layer with Faraday)
    ├── PromptCache (optional in-memory cache)
    ├── TextPromptClient (text prompt wrapper)
    └── ChatPromptClient (chat prompt wrapper)
```

## Roadmap

See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) and [TRACING_DESIGN.md](TRACING_DESIGN.md) for detailed roadmaps.

**Prompt Management (Completed):**
- ✅ Phase 0: Foundation & Project Setup
- ✅ Phase 1: HTTP Client with Authentication
- ✅ Phase 2: Text & Chat Prompt Clients
- ✅ Phase 3: Variable Substitution (Mustache)
- ✅ Phase 4: In-Memory Caching with TTL
- ✅ Phase 5: Global Configuration & Singleton

**Tracing & Observability (Completed):**
- ✅ Phase T0: OpenTelemetry Setup
- ✅ Phase T1: Langfuse Exporter (OTel → Langfuse Events)
- ✅ Phase T2: Ruby API Wrapper (Block-based API)
- ✅ Phase T4: Prompt Linking (Automatic)

**Coming Soon:**
- 🚧 Phase T3: Async Processing (ActiveJob/Sidekiq)
- 🚧 Phase T5: Cost Tracking (Automatic calculation)
- 🚧 Phase T6: Distributed Tracing (W3C Trace Context)
- 🚧 Phase T7: APM Integration (Multi-exporter)
- 🚧 Phase 8: CRUD Operations (create/update prompts)
- 🚧 Phase 10: Documentation & 1.0 Release

## Contributing

We welcome contributions! Please:

1. Check [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) to see what's being worked on
2. Open an issue to discuss your idea
3. Fork the repo and create a feature branch
4. Write tests for your changes
5. Ensure `bundle exec rspec` and `bundle exec rubocop` pass
6. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Links

- [Langfuse Documentation](https://langfuse.com/docs)
- [Langfuse API Reference](https://api.reference.langfuse.com)
- [Design Document](langfuse-ruby-prompt-management-design.md)
- [Implementation Plan](IMPLEMENTATION_PLAN.md)
- [Progress Tracker](PROGRESS.md)

## Support

- [GitHub Issues](https://github.com/langfuse/langfuse-ruby/issues)
- [Langfuse Discord](https://langfuse.com/discord)

---

**Note**: This SDK includes production-ready prompt management and LLM tracing (built on OpenTelemetry). Advanced features like ingestion batching and APM export are under active development. Check [PROGRESS.md](PROGRESS.md) for current status.
