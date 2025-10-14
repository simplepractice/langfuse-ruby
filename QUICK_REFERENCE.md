# Quick Reference - Langfuse Ruby Gem

Quick reference for key design decisions and patterns to follow during implementation.

---

## Core Design Principles

### 1. LaunchDarkly-Inspired API (IMPORTANT!)

**Flat API surface** - everything on Client:
```ruby
# ✅ YES - LaunchDarkly style
client.get_prompt("name")
client.compile_prompt("name", variables: {})
client.create_prompt(...)

# ❌ NO - Nested managers
client.prompt.get("name")
client.prompt.compile(...)
```

### 2. Global Configuration Pattern

```ruby
# Rails initializer
Langfuse.configure do |config|
  config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
  config.secret_key = ENV['LANGFUSE_SECRET_KEY']
  config.cache_ttl = 60
end

# Use global singleton
client = Langfuse.client
```

### 3. Ruby Conventions

- **snake_case** for all methods: `get_prompt`, not `getPrompt`
- **Symbol keys** in hashes: `{ role: :user }`, not `{ "role" => "user" }`
- **Keyword arguments**: `get_prompt(name, version: 2)`, not `get_prompt(name, { version: 2 })`
- **Blocks for config**: `configure { |c| ... }`

---

## Key Architecture Decisions

### Dependencies (Minimal!)

**Phase 1 (MVP):**
- `faraday ~> 2.0` - HTTP client
- `faraday-retry ~> 2.0` - Retry logic
- `mustache ~> 1.1` - Variable substitution
- Dev: `rspec`, `webmock`, `simplecov`

**Phase 2 (Advanced):**
- `concurrent-ruby ~> 1.2` - Thread pool for cache refresh
- Dev: `vcr` - HTTP recording

**No Rails dependency!** - Should work in any Ruby project

### Caching Strategy

**Phase 1:** Simple in-memory with TTL
```ruby
cache.set(key, value, ttl_seconds)
item = cache.get_including_expired(key)
```

**Phase 2:** Add stale-while-revalidate
- Return stale immediately
- Refresh in background
- Stampede protection

**Phase 3:** Optional Rails.cache backend

### Error Handling

**Graceful with fallbacks** (recommended):
```ruby
prompt = client.get_prompt("greeting",
  fallback: "Hello {{name}}!",
  type: :text
)
# Never raises - returns fallback on error
```

**Traditional exceptions** (also supported):
```ruby
begin
  prompt = client.get_prompt("greeting")
rescue Langfuse::NotFoundError => e
  # handle error
end
```

### Thread Safety

- Use `Mutex` for cache synchronization
- Safe for Rails multi-threaded servers
- Thread pool for background refreshes

---

## API Design

### Client Methods (Flattened!)

```ruby
# Core prompt operations
client.get_prompt(name, **options) → TextPromptClient | ChatPromptClient
client.get_prompt_detail(name, **options) → Hash (with metadata)
client.compile_prompt(name, variables:, placeholders:, **options) → String | Array

# CRUD operations (Phase 2)
client.create_prompt(**body) → TextPromptClient | ChatPromptClient
client.update_prompt(name:, version:, labels:) → Hash
client.invalidate_cache(name) → nil

# Utility
client.initialized? → Boolean
```

### Options for get_prompt

```ruby
get_prompt(name,
  version: nil,           # Specific version number
  label: "production",    # Label filter
  cache_ttl: 60,          # Cache TTL in seconds
  fallback: nil,          # Fallback content (String or Array)
  type: nil,              # Force type (:text or :chat)
  timeout: nil            # Request timeout
)
```

### TextPromptClient

```ruby
prompt = client.get_prompt("greeting", type: :text)

# Attributes
prompt.name        # String
prompt.version     # Integer
prompt.prompt      # String
prompt.config      # Hash
prompt.labels      # Array<String>
prompt.tags        # Array<String>
prompt.type        # Symbol :text
prompt.is_fallback # Boolean

# Methods
prompt.compile(variables = {}) → String
prompt.to_langchain → String (Phase 3)
prompt.to_json → String
```

### ChatPromptClient

```ruby
prompt = client.get_prompt("chat", type: :chat)

# Attributes (same as Text)
prompt.prompt  # Array<Hash> of messages

# Methods
prompt.compile(variables = {}, placeholders = {}) → Array<Hash>
prompt.to_langchain(placeholders: {}) → Array (Phase 3)
prompt.to_json → String
```

---

## File Structure

```
langfuse-ruby/
├── lib/
│   ├── langfuse.rb                    # Main entry point, global config
│   └── langfuse/
│       ├── version.rb
│       ├── config.rb                  # Configuration object
│       ├── client.rb                  # Main client (flattened API)
│       ├── api_client.rb              # HTTP layer
│       ├── prompt_cache.rb            # Caching logic
│       ├── text_prompt_client.rb      # Text prompt wrapper
│       ├── chat_prompt_client.rb      # Chat prompt wrapper
│       └── errors.rb                  # Error classes
├── spec/
│   ├── spec_helper.rb
│   └── langfuse/
│       ├── config_spec.rb
│       ├── client_spec.rb
│       └── ... (one per class)
├── langfuse-ruby.gemspec
├── Gemfile
├── README.md
├── CHANGELOG.md
└── LICENSE
```

---

## Testing Strategy

### Test Coverage Target: >90%

### Test Types

1. **Unit tests** - Test each class in isolation
2. **Integration tests** - Test Client → ApiClient → (mocked HTTP)
3. **VCR tests** - Record real API responses (Phase 2)
4. **Performance tests** - Cache latency benchmarks

### Mocking Strategy

**WebMock for HTTP:**
```ruby
stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
  .to_return(status: 200, body: response_json)
```

**Instance doubles for dependencies:**
```ruby
let(:api_client) { instance_double(Langfuse::ApiClient) }
allow(api_client).to receive(:get_prompt).and_return(response)
```

### Common Test Patterns

```ruby
RSpec.describe Langfuse::Client do
  let(:config) do
    Langfuse::Config.new do |c|
      c.public_key = "test_pk"
      c.secret_key = "test_sk"
    end
  end
  let(:client) { described_class.new(config) }

  describe "#get_prompt" do
    context "with cache miss" do
      it "fetches from API and caches result"
    end

    context "with cache hit" do
      it "returns cached prompt without API call"
    end

    context "with fallback" do
      it "returns fallback on API error"
    end
  end
end
```

---

## Variable Substitution

### Mustache Templating

**Template syntax:**
```
Hello {{name}} from {{city}}!
```

**Compilation:**
```ruby
# Input
variables = { name: "Alice", city: "SF" }

# Output
"Hello Alice from SF!"
```

**Key points:**
- Logic-less (no conditionals, no loops)
- Same syntax as JavaScript SDK
- Secure (no code execution)

### LangChain Transformation (Phase 3)

**Langfuse → LangChain:**
```ruby
"Hello {{name}}!"  →  "Hello {name}!"
```

Simply replace `{{var}}` with `{var}`

---

## Chat Prompt Placeholders (Phase 2)

### Placeholder in Template

```ruby
[
  { type: "chatmessage", role: "system", content: "You are {{role}}." },
  { type: "placeholder", name: "examples" },
  { role: "user", content: "{{question}}" }
]
```

### Compilation with Placeholder

```ruby
prompt.compile(
  { role: "helper", question: "What?" },
  {
    examples: [
      { role: "user", content: "Hi" },
      { role: "assistant", content: "Hello!" }
    ]
  }
)

# Result (flattened):
[
  { role: "system", content: "You are helper." },
  { role: "user", content: "Hi" },
  { role: "assistant", content: "Hello!" },
  { role: "user", content: "What?" }
]
```

---

## Code Style Guidelines

### Naming Conventions

- **Classes:** `PascalCase` (e.g., `TextPromptClient`)
- **Methods:** `snake_case` (e.g., `get_prompt`)
- **Constants:** `SCREAMING_SNAKE_CASE` (e.g., `DEFAULT_TTL`)
- **Instance vars:** `@snake_case` (e.g., `@api_client`)

### Documentation

Use YARD format:
```ruby
# Get a prompt with caching and fallback support
#
# @param name [String] Prompt name
# @param options [Hash] Options hash
# @option options [Integer] :version Specific version
# @option options [String] :fallback Fallback content
# @return [TextPromptClient, ChatPromptClient]
# @raise [ApiError] if fetch fails and no fallback
#
# @example
#   prompt = client.get_prompt("greeting", fallback: "Hello!")
def get_prompt(name, **options)
  # ...
end
```

### Error Messages

Be descriptive and actionable:
```ruby
raise ArgumentError, "Text prompt fallback must be a String, got #{fallback.class}. " \
                     "For chat prompts, use an Array of message hashes."
```

---

## When to Ask Questions

**Before implementing, ask if:**
1. Design decision is unclear or ambiguous
2. Multiple valid approaches exist
3. Trade-off needs to be made (performance vs simplicity)
4. LaunchDarkly pattern isn't clear from docs

**Examples:**
- "Should `get_prompt` raise or return nil when not found?"
  → Design doc says: Return fallback or raise (depending on options)
- "How should we handle concurrent cache refreshes?"
  → Design doc says: Stampede protection (Phase 2)

---

## Quick Win Checkpoints

After each phase, we should be able to:

- **Phase 0:** Run `bundle exec rspec` (even if no tests)
- **Phase 1:** Fetch a real prompt from Langfuse API
- **Phase 2:** Get a prompt object with metadata
- **Phase 3:** Compile a prompt with variables
- **Phase 4:** See cache hit/miss in logs
- **Phase 5:** Use `Langfuse.client` in test script
- **Phase 6:** Handle API errors gracefully with fallback

---

## Resources

- **Design Doc:** `langfuse-ruby-prompt-management-design.md`
- **Implementation Plan:** `IMPLEMENTATION_PLAN.md`
- **Progress Tracker:** `PROGRESS.md`
- **LaunchDarkly Ruby SDK:** https://github.com/launchdarkly/ruby-server-sdk
- **Langfuse API Docs:** https://langfuse.com/docs/api
- **TypeScript SDK:** https://github.com/langfuse/langfuse-js

---

Last Updated: 2025-10-13
