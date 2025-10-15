# Langfuse Ruby SDK

Official Ruby SDK for [Langfuse](https://langfuse.com) - Open-source LLM observability and prompt management.

[![Gem Version](https://badge.fury.io/rb/langfuse.svg)](https://badge.fury.io/rb/langfuse)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.2.0-ruby.svg)](https://www.ruby-lang.org/en/)
[![Test Coverage](https://img.shields.io/badge/coverage-99.6%25-brightgreen.svg)](coverage)

## Features

✅ **Prompt Management** - Fetch and compile prompts with variable substitution
✅ **In-Memory Caching** - Thread-safe caching with TTL and LRU eviction
✅ **Text & Chat Prompts** - Support for both simple text and chat/completion prompts
✅ **Mustache Templating** - Logic-less variable substitution
✅ **Rails-Friendly** - Global configuration pattern with `Langfuse.configure`
✅ **Thread-Safe** - Safe for multi-threaded environments
🚧 **LLM Tracing** - Coming soon
🚧 **Observability** - Coming soon

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

# Compile with variables
email = prompt.compile(
  customer_name: "Alice",
  order_number: "12345",
  total: "$99.99"
)
puts email
# => "Dear Alice, your order #12345 for $99.99 has shipped!"
```

### Chat Prompts

Chat prompts return arrays of messages for LLM APIs (OpenAI, Anthropic, etc.):

```ruby
# Fetch a chat prompt
prompt = Langfuse.client.get_prompt("support-assistant")

# Compile with variables
messages = prompt.compile(
  company_name: "Acme Corp",
  support_level: "premium"
)

# Use with OpenAI
require 'openai'
client = OpenAI::Client.new
response = client.chat(
  parameters: {
    model: "gpt-4",
    messages: messages  # Ready to use!
  }
)
```

Example output:
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

```ruby
# Nested objects
prompt.compile(
  user: {
    name: "Alice",
    email: "alice@example.com"
  }
)
# Template: "Hello {{user.name}}, we'll email you at {{user.email}}"
# Result: "Hello Alice, we'll email you at alice@example.com"

# Lists
prompt.compile(
  items: [
    { name: "Apple", price: 1.99 },
    { name: "Banana", price: 0.99 }
  ]
)
# Template: "{{#items}}• {{name}}: ${{price}}\n{{/items}}"
# Result: "• Apple: $1.99\n• Banana: $0.99\n"

# HTML escaping (automatic by default)
prompt.compile(content: "<script>alert('xss')</script>")
# Result: "&lt;script&gt;alert('xss')&lt;/script&gt;"

# Disable escaping with triple braces
# Template: "{{{raw_html}}}"
prompt.compile(raw_html: "<strong>Bold</strong>")
# Result: "<strong>Bold</strong>"
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

See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for the detailed roadmap.

**Completed:**
- ✅ Phase 0: Foundation & Project Setup
- ✅ Phase 1: HTTP Client with Authentication
- ✅ Phase 2: Text & Chat Prompt Clients
- ✅ Phase 3: Variable Substitution (Mustache)
- ✅ Phase 4: In-Memory Caching with TTL
- ✅ Phase 5: Global Configuration & Singleton

**Coming Soon:**
- 🚧 Phase 6: Convenience Features (error recovery, helpers)
- 🚧 Phase 7: Advanced Caching (LRU, background refresh)
- 🚧 Phase 8: CRUD Operations (create/update prompts)
- 🚧 Phase 9: LangChain Integration
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

**Note**: This SDK is under active development. Prompt management features are production-ready, but LLM tracing and observability features are coming soon. Check [PROGRESS.md](PROGRESS.md) for current status.
