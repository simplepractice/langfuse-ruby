# Langfuse Ruby SDK

Ruby SDK for [Langfuse](https://langfuse.com) - Open-source LLM observability and prompt management.

[![Gem Version](https://badge.fury.io/rb/langfuse.svg)](https://badge.fury.io/rb/langfuse)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.2.0-ruby.svg)](https://www.ruby-lang.org/en/)
[![Test Coverage](https://img.shields.io/badge/coverage-99.6%25-brightgreen.svg)](coverage)

## Features

- 🎯 **Prompt Management** - Fetch and compile prompts with variable substitution
- 📊 **LLM Tracing** - Built on OpenTelemetry for distributed tracing
- ⚡ **Flexible Caching** - In-memory or Rails.cache (Redis) backends with TTL
- 💬 **Text & Chat Prompts** - Support for both simple text and chat/completion formats
- 🔧 **Mustache Templating** - Logic-less variable substitution with nested objects and lists
- 🔄 **Automatic Retries** - Built-in retry logic with exponential backoff
- 🛡️ **Fallback Support** - Graceful degradation when API is unavailable
- 🚀 **Rails-Friendly** - Global configuration pattern with `Langfuse.configure`

## Installation

Add to your Gemfile:

```ruby
gem 'langfuse'
```

Then run:

```bash
bundle install
```

## Quick Start

### Configuration

```ruby
# config/initializers/langfuse.rb (Rails)
Langfuse.configure do |config|
  config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
  config.secret_key = ENV['LANGFUSE_SECRET_KEY']
  config.base_url = "https://cloud.langfuse.com"  # Optional (default)
  config.cache_ttl = 60           # Cache prompts for 60 seconds (optional)
  config.cache_backend = :memory  # :memory (default) or :rails for distributed cache
  config.timeout = 5              # Request timeout in seconds (optional)
end
```

### Basic Usage

```ruby
# Use the global singleton client
client = Langfuse.client
prompt = client.get_prompt("greeting")
text = prompt.compile(name: "Alice")
puts text  # => "Hello Alice!"
```

## Prompt Management

### Text Prompts

Text prompts are simple string templates with Mustache variables:

```ruby
# Fetch a text prompt
prompt = Langfuse.client.get_prompt("email-template")

# Access metadata
prompt.name        # => "email-template"
prompt.version     # => 3
prompt.labels      # => ["production"]
prompt.tags        # => ["email", "customer"]

# Compile with variables
email = prompt.compile(
  customer_name: "Alice",
  order_number: "12345",
  total: "$99.99"
)
# => "Dear Alice, your order #12345 for $99.99 has shipped!"
```

### Chat Prompts

Chat prompts return arrays of messages ready for LLM APIs:

```ruby
# Fetch a chat prompt
prompt = Langfuse.client.get_prompt("support-assistant")

# Compile with variables
messages = prompt.compile(
  company_name: "Acme Corp",
  support_level: "premium"
)
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
    messages: messages
  }
)
```

### Versioning

```ruby
# Fetch specific version
prompt = Langfuse.client.get_prompt("greeting", version: 2)

# Fetch by label
production_prompt = Langfuse.client.get_prompt("greeting", label: "production")
```

### Advanced Templating

The SDK uses [Mustache](https://mustache.github.io/) for powerful templating:

```ruby
# Nested objects
prompt.compile(
  user: { name: "Alice", email: "alice@example.com" }
)
# Template: "Hello {{user.name}}, we'll email you at {{user.email}}"
# Result: "Hello Alice, we'll email you at alice@example.com"

# Lists/Arrays
prompt.compile(
  items: [
    { name: "Apple", price: 1.99 },
    { name: "Banana", price: 0.99 }
  ]
)
# Template: "{{#items}}• {{name}}: ${{price}}\n{{/items}}"
# Result: "• Apple: $1.99\n• Banana: $0.99"

# HTML escaping (automatic)
prompt.compile(content: "<script>alert('xss')</script>")
# Template: "User input: {{content}}"
# Result: "User input: &lt;script&gt;alert('xss')&lt;/script&gt;"

# Raw output (triple braces to skip escaping)
prompt.compile(raw_html: "<strong>Bold</strong>")
# Template: "{{{raw_html}}}"
# Result: "<strong>Bold</strong>"
```

See [Mustache documentation](https://mustache.github.io/mustache.5.html) for more templating features.

### Convenience Methods

```ruby
# One-liner: fetch and compile
text = Langfuse.client.compile_prompt("greeting", variables: { name: "Alice" })

# With fallback for graceful degradation
prompt = Langfuse.client.get_prompt(
  "greeting",
  fallback: "Hello {{name}}!",
  type: :text
)
```

## LLM Tracing & Observability

The SDK provides comprehensive LLM tracing built on **OpenTelemetry**. Traces capture LLM calls, nested operations, token usage, and costs.

### Basic Example

```ruby
Langfuse.trace(name: "chat-completion", user_id: "user-123") do |trace|
  trace.generation(
    name: "openai-call",
    model: "gpt-4",
    input: [{ role: "user", content: "Hello!" }]
  ) do |gen|
    response = openai_client.chat(
      parameters: {
        model: "gpt-4",
        messages: [{ role: "user", content: "Hello!" }]
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

### RAG Pipeline Example

```ruby
Langfuse.trace(name: "rag-query", user_id: "user-456") do |trace|
  # Document retrieval
  docs = trace.span(name: "retrieval", input: { query: "What is Ruby?" }) do |span|
    results = vector_db.search(query_embedding, limit: 5)
    span.output = { count: results.size }
    results
  end

  # LLM generation with context
  trace.generation(
    name: "gpt4-completion",
    model: "gpt-4",
    input: build_prompt_with_context(docs)
  ) do |gen|
    response = openai_client.chat(...)
    gen.output = response.choices.first.message.content
    gen.usage = {
      prompt_tokens: response.usage.prompt_tokens,
      completion_tokens: response.usage.completion_tokens
    }
  end
end
```

### Automatic Prompt Linking

Prompts fetched via the SDK are automatically linked to your traces:

```ruby
prompt = Langfuse.client.get_prompt("support-assistant", version: 3)

Langfuse.trace(name: "support-query") do |trace|
  trace.generation(
    name: "response",
    model: "gpt-4",
    prompt: prompt  # Automatically captured in trace!
  ) do |gen|
    messages = prompt.compile(customer_name: "Alice")
    response = openai_client.chat(parameters: { model: "gpt-4", messages: messages })
    gen.output = response.choices.first.message.content
  end
end
```

### OpenTelemetry Integration

The SDK is built on OpenTelemetry, which means:
- **Automatic Context Propagation**: Trace context flows through your application
- **APM Integration**: Traces appear in Datadog, New Relic, Honeycomb, etc.
- **W3C Trace Context**: Standard distributed tracing across microservices
- **Rich Instrumentation**: Works with existing OTel instrumentation (HTTP, Rails, Sidekiq)

For more tracing examples and advanced usage, see [Tracing Guide](docs/TRACING.md).

## Configuration

All configuration options:

```ruby
Langfuse.configure do |config|
  # Required: Authentication
  config.public_key = "pk_..."
  config.secret_key = "sk_..."

  # Optional: API Settings
  config.base_url = "https://cloud.langfuse.com"  # Default
  config.timeout = 5                              # Seconds (default: 5)

  # Optional: Caching
  config.cache_backend = :memory      # :memory (default) or :rails
  config.cache_ttl = 60               # Cache TTL in seconds (default: 60, 0 = disabled)
  config.cache_max_size = 1000        # Max cached prompts (default: 1000, only for :memory backend)
  config.cache_lock_timeout = 10      # Lock timeout in seconds (default: 10, only for :rails backend)

  # Optional: Logging
  config.logger = Rails.logger    # Custom logger (default: Logger.new($stdout))
end
```

### Environment Variables

Configuration can also be loaded from environment variables:

```bash
export LANGFUSE_PUBLIC_KEY="pk_..."
export LANGFUSE_SECRET_KEY="sk_..."
export LANGFUSE_BASE_URL="https://cloud.langfuse.com"
```

```ruby
Langfuse.configure do |config|
  # Keys are automatically loaded from ENV if not explicitly set
end
```

### Instance-Based Configuration

For non-global usage:

```ruby
config = Langfuse::Config.new do |c|
  c.public_key = "pk_..."
  c.secret_key = "sk_..."
end

client = Langfuse::Client.new(config)
```

## Caching

The SDK supports two caching backends:

### In-Memory Cache (Default)

Built-in thread-safe in-memory caching with TTL and LRU eviction:

```ruby
Langfuse.configure do |config|
  config.cache_backend = :memory      # Default
  config.cache_ttl = 60               # Cache for 60 seconds
  config.cache_max_size = 1000        # Max 1000 prompts in memory
end

# First call hits the API
prompt1 = Langfuse.client.get_prompt("greeting")  # API call

# Second call uses cache (within TTL)
prompt2 = Langfuse.client.get_prompt("greeting")  # Cached!

# Different versions are cached separately
v1 = Langfuse.client.get_prompt("greeting", version: 1)  # API call
v2 = Langfuse.client.get_prompt("greeting", version: 2)  # API call
```

**In-Memory Cache Features:**
- Thread-safe with Monitor-based synchronization
- TTL-based expiration
- LRU eviction when max_size is reached
- Perfect for single-process apps, scripts, and Sidekiq workers
- No external dependencies

### Rails.cache Backend (Distributed)

For multi-process deployments (e.g., large Rails apps with many Passenger/Puma workers):

```ruby
# config/initializers/langfuse.rb
Langfuse.configure do |config|
  config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
  config.secret_key = ENV['LANGFUSE_SECRET_KEY']
  config.cache_backend = :rails      # Use Rails.cache (typically Redis)
  config.cache_ttl = 300              # 5 minutes
end
```

**Rails.cache Backend Features:**
- Shared cache across all processes and servers
- Distributed caching with Redis/Memcached
- **Automatic stampede protection** with distributed locks
- Exponential backoff (50ms, 100ms, 200ms) when waiting for locks
- No max_size limit (managed by Redis/Memcached)
- Ideal for large-scale deployments (100+ processes)

**How Stampede Protection Works:**

When using Rails.cache backend, the SDK automatically prevents "thundering herd" problems:

1. **Cache Miss**: First process acquires distributed lock, fetches from API
2. **Concurrent Requests**: Other processes wait (exponential backoff) instead of hitting API
3. **Cache Populated**: Waiting processes read from cache once first process completes
4. **Fallback**: If lock holder crashes, lock auto-expires (configurable timeout)

```ruby
# Configure lock timeout (default: 10 seconds)
Langfuse.configure do |config|
  config.cache_backend = :rails
  config.cache_lock_timeout = 15  # Lock expires after 15s
end
```

This is **automatic** for Rails.cache backend - no additional configuration needed!

**When to use Rails.cache:**
- Large Rails apps with many worker processes (Passenger, Puma, Unicorn)
- Multiple servers sharing the same prompt cache
- Deploying with 100+ processes that all need consistent cache
- Already using Redis for Rails.cache

**When to use in-memory cache:**
- Single-process applications
- Scripts and background jobs
- Smaller deployments (< 10 processes)
- When you want zero external dependencies

## Error Handling

```ruby
begin
  prompt = Langfuse.client.get_prompt("my-prompt")
rescue Langfuse::NotFoundError => e
  puts "Prompt not found: #{e.message}"
rescue Langfuse::UnauthorizedError => e
  puts "Authentication failed: #{e.message}"
rescue Langfuse::ApiError => e
  puts "API error: #{e.message}"
end
```

**Exception Hierarchy:**
```
StandardError
└── Langfuse::Error
    ├── Langfuse::ConfigurationError
    └── Langfuse::ApiError
        ├── Langfuse::NotFoundError    (404)
        └── Langfuse::UnauthorizedError (401)
```

## Testing

The SDK is designed to be test-friendly:

```ruby
# RSpec example
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

## API Reference

### Client Methods

```ruby
# Get a prompt (returns TextPromptClient or ChatPromptClient)
client.get_prompt(name, version: nil, label: nil)

# Get and compile in one call
client.compile_prompt(name, variables: {}, version: nil, label: nil, fallback: nil, type: nil)
```

### Prompt Client Methods

```ruby
# TextPromptClient
prompt.compile(variables = {})  # Returns String

# ChatPromptClient
prompt.compile(variables = {})  # Returns Array of message hashes

# Both have these properties:
prompt.name        # String
prompt.version     # Integer
prompt.prompt      # String (text) or Array (chat)
prompt.labels      # Array
prompt.tags        # Array
prompt.config      # Hash
```

### Tracing Methods

```ruby
# Create a trace
Langfuse.trace(name:, user_id: nil, session_id: nil, metadata: {}) do |trace|
  # Add spans, generations, events
end

# Add a generation (LLM call)
trace.generation(name:, model:, input:, prompt: nil) do |gen|
  gen.output = "..."
  gen.usage = { prompt_tokens: 10, completion_tokens: 20 }
end

# Add a span (any operation)
trace.span(name:, input: nil) do |span|
  span.output = "..."
  span.metadata = { ... }
end

# Add an event (point-in-time)
trace.event(name:, input: nil, output: nil)
```

See [API documentation](https://langfuse.com/docs) for complete reference.

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

# Run linter
bundle exec rubocop -a
```

## Roadmap & Status

**Current Status:** Production-ready with 99.6% test coverage

For detailed implementation plans and progress, see:
- [IMPLEMENTATION_PLAN_V2.md](IMPLEMENTATION_PLAN_V2.md) - Detailed roadmap
- [PROGRESS.md](PROGRESS.md) - Current status and milestones

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

1. Check existing issues and roadmap
2. Open an issue to discuss your idea
3. Fork the repo and create a feature branch
4. Write tests for your changes
5. Ensure `bundle exec rspec` and `bundle exec rubocop` pass
6. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Links

- [Langfuse Documentation](https://langfuse.com/docs)
- [API Reference](https://api.reference.langfuse.com)
- [GitHub Issues](https://github.com/langfuse/langfuse-ruby/issues)

## Support

Need help? Open an issue on [GitHub](https://github.com/langfuse/langfuse-ruby/issues).
