# Langfuse Ruby SDK - Prompt Management Technical Design

**Document Version:** 1.0
**Date:** 2025-10-02
**Author:** Technical Architecture Team
**Status:** Design Document

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Architecture Overview](#architecture-overview)
4. [Component Design](#component-design)
5. [API Design](#api-design)
6. [Caching Strategy](#caching-strategy)
7. [REST API Integration](#rest-api-integration)
8. [Variable Substitution](#variable-substitution)
9. [Implementation Phases](#implementation-phases)
10. [Testing Strategy](#testing-strategy)
11. [Dependencies](#dependencies)
12. [Code Examples](#code-examples)
13. [Migration Strategy](#migration-strategy)
14. [Trade-offs and Alternatives](#trade-offs-and-alternatives)
15. [Open Questions](#open-questions)

---

## Executive Summary

This document outlines the technical design for adding prompt management functionality to the `langfuse-ruby` gem, achieving feature parity with the JavaScript SDK's prompt management capabilities while adhering to Ruby idioms and best practices.

### Key Objectives

- **Feature Parity**: Match JavaScript SDK's prompt management functionality
- **Ruby Conventions**: Follow Ruby/Rails conventions (snake_case, blocks, Rails.cache integration)
- **Thread Safety**: Ensure concurrent request safety for Rails applications
- **Performance**: Implement intelligent caching with stale-while-revalidate pattern
- **Developer Experience**: Provide intuitive, well-documented API

### Success Metrics

- All JavaScript SDK prompt features available in Ruby
- Sub-100ms cache hits for prompt retrieval
- Zero breaking changes to existing langfuse-ruby API
- Comprehensive test coverage (>90%)
- Thread-safe for production Rails applications

---

## Design Philosophy: LaunchDarkly-Inspired API

### Why LaunchDarkly as a Model?

The LaunchDarkly Ruby SDK is widely regarded as one of the best-designed Ruby gems, with exceptional developer ergonomics. This design incorporates several key patterns from LaunchDarkly:

**1. Flat API Surface**
- LaunchDarkly: `client.variation('flag', user, default)`
- Langfuse: `client.get_prompt('name', fallback: "...")`
- Benefit: Minimal cognitive overhead, everything on the client

**2. Required Defaults for Resilience**
- LaunchDarkly: Every call requires a default value, never throws
- Langfuse: Encourage fallbacks, gracefully degrade on errors
- Benefit: Production resilience built-in

**3. Configuration Object Pattern**
- LaunchDarkly: `Config` class with block initialization
- Langfuse: `Langfuse::Config` with global configuration
- Benefit: Clean Rails initialization, centralized settings

**4. Simple Return Values**
- LaunchDarkly: `variation` returns value, `variation_detail` adds metadata
- Langfuse: `get_prompt` returns client, `get_prompt_detail` adds metadata
- Benefit: Simple common case, detailed when needed

**5. Global Singleton Pattern**
- LaunchDarkly: Initialize once, use everywhere
- Langfuse: `Langfuse.client` for Rails convenience
- Benefit: No prop-drilling, simpler service objects

### API Comparison

| Feature | LaunchDarkly | Langfuse (This Design) |
|---------|-------------|------------------------|
| Initialization | `LDClient.new(sdk_key, config)` | `Client.new(config)` |
| Global config | `Config.new { \|c\| ... }` | `Langfuse.configure { \|c\| ... }` |
| Global client | Manual singleton | `Langfuse.client` |
| Primary method | `variation(key, user, default)` | `get_prompt(name, fallback: ...)` |
| Detail variant | `variation_detail(key, user, default)` | `get_prompt_detail(name, ...)` |
| Error handling | Returns default, logs error | Returns fallback or raises |
| State check | `initialized?` | `initialized?` |

---

## Problem Statement

### Current State

The `langfuse-ruby` gem (v0.1.4) provides:
- Tracing functionality (trace, span, generation, event, score)
- Basic configuration and authentication
- Async processing via Sidekiq integration

**Missing capabilities:**
- Prompt retrieval and management
- Prompt creation and updates
- Variable substitution/compilation
- Intelligent caching
- Placeholder support for chat prompts
- LangChain integration helpers

### Business Context

Langfuse prompts enable:
- **Centralized Prompt Management**: Single source of truth for LLM prompts
- **Version Control**: Track prompt changes over time
- **A/B Testing**: Multiple prompt versions with labels
- **Rapid Iteration**: Update prompts without code deployment
- **Collaboration**: Product/non-technical teams can manage prompts

### Target Users

1. **Rails Developers**: Building LLM-powered features in production Rails apps
2. **Data Scientists**: Experimenting with prompt engineering in Ruby notebooks
3. **Platform Teams**: Managing LLM integrations across microservices

---

## Architecture Overview

### High-Level System Design

```
┌─────────────────────────────────────────────────────────────┐
│               Langfuse Module (Global Config)                │
│                                                              │
│  • configure { |config| ... }                                │
│  • client (singleton)                                        │
│  • reset! (testing)                                          │
└──────────────────────────┬───────────────────────────────────┘
                           │
                           │ creates
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    Langfuse::Client                          │
│                                                              │
│  Prompt Methods (Flattened API):                            │
│  • get_prompt(name, **options)                              │
│  • get_prompt_detail(name, **options)                       │
│  • compile_prompt(name, variables:, placeholders:)          │
│  • create_prompt(**body)                                    │
│  • update_prompt(name:, version:, labels:)                  │
│  • invalidate_cache(name)                                   │
│  • initialized?                                             │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         Langfuse::PromptCache                       │   │
│  │                                                     │   │
│  │  • get_including_expired(key)                       │   │
│  │  • set(key, value, ttl)                             │   │
│  │  • invalidate(prompt_name)                          │   │
│  │  • trigger_background_refresh                       │   │
│  │  • Thread-safe operations (Mutex)                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         Langfuse::ApiClient                         │   │
│  │                                                     │   │
│  │  • get_prompt(name, version:, label:)               │   │
│  │  • create_prompt(body)                              │   │
│  │  • update_prompt_version(name, version, labels)     │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ HTTP (Basic Auth)
                           ▼
                ┌──────────────────────┐
                │   Langfuse API       │
                │  (cloud.langfuse.com)│
                └──────────────────────┘


┌─────────────────────────────────────────────────────────────┐
│              Prompt Client Classes                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │  Langfuse::TextPromptClient                        │     │
│  │                                                    │     │
│  │  • compile(variables = {})                         │     │
│  │  • to_langchain                                    │     │
│  │  • name, version, config, labels, tags             │     │
│  └────────────────────────────────────────────────────┘     │
│                                                              │
│  ┌────────────────────────────────────────────────────┐     │
│  │  Langfuse::ChatPromptClient                        │     │
│  │                                                    │     │
│  │  • compile(variables = {}, placeholders = {})      │     │
│  │  • to_langchain(placeholders: {})                  │     │
│  │  • name, version, config, labels, tags             │     │
│  └────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Thread-Safe? |
|-----------|---------------|--------------|
| `Langfuse` (module) | Global configuration, singleton client | N/A |
| `Langfuse::Config` | Configuration object (keys, cache, logger) | N/A |
| `Langfuse::Client` | Main API surface, prompt operations, caching logic | Yes |
| `Langfuse::PromptCache` | In-memory TTL cache, stale-while-revalidate | Yes |
| `Langfuse::ApiClient` | HTTP communication with Langfuse API | Yes |
| `Langfuse::TextPromptClient` | Text prompt manipulation, compilation | N/A (immutable) |
| `Langfuse::ChatPromptClient` | Chat prompt manipulation, placeholders | N/A (immutable) |

### Integration with Existing Gem

The prompt management system integrates seamlessly:

```ruby
# Global configuration (Rails initializer)
Langfuse.configure do |config|
  config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
  config.secret_key = ENV['LANGFUSE_SECRET_KEY']
end

# NEW: Get global client
client = Langfuse.client

# NEW: Prompt management (flattened API)
prompt = client.get_prompt("greeting")
compiled = prompt.compile(name: "Alice")

# Or: One-step convenience method
text = client.compile_prompt("greeting", variables: { name: "Alice" })

# Existing tracing (unchanged)
client.trace(name: "my-trace") do |trace|
  trace.generation(name: "llm-call", input: compiled)
end
```

---

## Component Design

### 1. Langfuse Module (Global Configuration)

**Purpose**: Provide global configuration and singleton client for Rails convenience.

```ruby
module Langfuse
  class << self
    attr_writer :configuration

    # Global configuration
    def configuration
      @configuration ||= Config.new
    end

    # Configure block (Rails initializer)
    def configure
      yield(configuration)
      configuration.validate!
    end

    # Global singleton client
    def client
      @client ||= Client.new(configuration)
    end

    # Reset for testing
    def reset!
      @configuration = nil
      @client = nil
    end
  end
end
```

### 2. Langfuse::Config

**Purpose**: Configuration object for client initialization.

```ruby
module Langfuse
  class Config
    attr_accessor :public_key, :secret_key, :base_url, :timeout, :logger
    attr_accessor :cache_ttl, :cache_max_size, :cache_backend

    DEFAULT_BASE_URL = "https://cloud.langfuse.com"
    DEFAULT_TIMEOUT = 5
    DEFAULT_CACHE_TTL = 60
    DEFAULT_CACHE_MAX_SIZE = 1000

    def initialize
      @public_key = ENV['LANGFUSE_PUBLIC_KEY']
      @secret_key = ENV['LANGFUSE_SECRET_KEY']
      @base_url = ENV['LANGFUSE_BASE_URL'] || DEFAULT_BASE_URL
      @timeout = DEFAULT_TIMEOUT
      @cache_ttl = DEFAULT_CACHE_TTL
      @cache_max_size = DEFAULT_CACHE_MAX_SIZE
      @cache_backend = :memory
      @logger = defined?(Rails) ? Rails.logger : Logger.new($stdout)

      yield(self) if block_given?
    end

    def validate!
      raise ConfigurationError, "public_key is required" if public_key.nil? || public_key.empty?
      raise ConfigurationError, "secret_key is required" if secret_key.nil? || secret_key.empty?
    end
  end
end
```

**Usage Examples**:

```ruby
# Rails initializer
Langfuse.configure do |config|
  config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
  config.secret_key = ENV['LANGFUSE_SECRET_KEY']
  config.cache_ttl = 120  # 2 minutes
  config.logger = Rails.logger
end

# Anywhere in app
client = Langfuse.client  # Uses global config

# Or: Custom client for multi-tenant
config = Langfuse::Config.new do |c|
  c.public_key = tenant.langfuse_key
  c.secret_key = tenant.langfuse_secret
end
custom_client = Langfuse::Client.new(config)
```

### 3. Langfuse::Client (Flattened API)

**Purpose**: Main entry point for all prompt operations with caching logic.

```ruby
module Langfuse
  class Client
    attr_reader :config, :api_client, :cache, :logger

    # Initialize with Config object or inline options
    #
    # @param config_or_options [Config, Hash] Config object or hash of options
    def initialize(config_or_options = nil)
      if config_or_options.is_a?(Config)
        @config = config_or_options
      elsif config_or_options.is_a?(Hash)
        # Backward compatibility: convert hash to config
        @config = Config.new do |c|
          config_or_options.each { |k, v| c.send("#{k}=", v) if c.respond_to?("#{k}=") }
        end
      else
        @config = Langfuse.configuration
      end

      @config.validate!
      @logger = @config.logger
      @api_client = ApiClient.new(
        public_key: @config.public_key,
        secret_key: @config.secret_key,
        base_url: @config.base_url,
        timeout: @config.timeout,
        logger: @logger
      )
      @cache = PromptCache.new(
        max_size: @config.cache_max_size,
        logger: @logger
      )
    end

    # Check if client is initialized and ready
    def initialized?
      !@api_client.nil? && !@cache.nil?
    end

    # Get a prompt with caching and fallback support
    #
    # @param name [String] Prompt name
    # @param options [Hash] Options hash
    # @option options [Integer] :version Specific version
    # @option options [String] :label Label filter (default: "production")
    # @option options [Integer] :cache_ttl Cache TTL in seconds
    # @option options [String, Array<Hash>] :fallback Fallback content (RECOMMENDED)
    # @option options [Symbol] :type Force type (:text or :chat)
    # @option options [Integer] :timeout Request timeout in seconds
    #
    # @return [TextPromptClient, ChatPromptClient]
    # @raise [ApiError, NotFoundError] if fetch fails and no fallback
    #
    # @example Get with fallback (recommended)
    #   prompt = client.get_prompt("greeting",
    #     fallback: "Hello {{name}}!",
    #     type: :text
    #   )
    def get_prompt(name, **options)
      # Implementation: cache lookup -> API fetch -> fallback handling
      # (see full implementation in detailed design below)
    end

    # Get prompt with detailed metadata (for debugging/observability)
    #
    # @return [Hash] { prompt:, cached:, stale:, version:, fetch_time_ms:, source: }
    def get_prompt_detail(name, **options)
      # Implementation details
    end

    # Convenience method: Get and compile in one step
    #
    # @param name [String] Prompt name
    # @param variables [Hash] Variables for text prompts
    # @param placeholders [Hash] Placeholders for chat prompts
    # @param options [Hash] Same options as get_prompt
    #
    # @return [String, Array<Hash>] Compiled result
    #
    # @example
    #   text = client.compile_prompt("greeting",
    #     variables: { name: "Alice" },
    #     fallback: "Hello {{name}}!",
    #     type: :text
    #   )
    def compile_prompt(name, variables: {}, placeholders: {}, **options)
      prompt = get_prompt(name, **options)
      case prompt
      when TextPromptClient
        prompt.compile(variables)
      when ChatPromptClient
        prompt.compile(variables, placeholders)
      end
    end

    # Create a new prompt
    #
    # @param body [Hash] Prompt definition
    # @return [TextPromptClient, ChatPromptClient]
    def create_prompt(**body)
      validate_create_body!(body)
      response = api_client.create_prompt(body)
      build_prompt_client(response)
    end

    # Update prompt version labels
    #
    # @param name [String] Prompt name
    # @param version [Integer] Version number
    # @param labels [Array<String>] New labels
    #
    # @return [Hash] Updated prompt metadata
    def update_prompt(name:, version:, labels:)
      validate_update_params!(name, version, labels)
      response = api_client.update_prompt_version(name, version, labels)
      cache.invalidate(name)  # Only after successful update
      response
    end

    # Invalidate cache for a prompt
    def invalidate_cache(name)
      cache.invalidate(name)
      logger.info("Langfuse: Invalidated cache for #{name}")
    end

    private

    def validate_fallback_type!(fallback, type)
      case type
      when :text
        unless fallback.is_a?(String)
          raise ArgumentError, "Text prompt fallback must be a String, got #{fallback.class}"
        end
      when :chat
        unless fallback.is_a?(Array)
          raise ArgumentError, "Chat prompt fallback must be an Array, got #{fallback.class}"
        end
        fallback.each_with_index do |msg, i|
          unless msg.is_a?(Hash) && (msg.key?(:role) || msg.key?(:type))
            raise ArgumentError, "Chat fallback message #{i} must have :role or :type"
          end
        end
      end
    end

    # ... additional private methods for fetch_and_cache, build_prompt_client, etc.
  end
end
```

**Key Design Decisions:**

1. **Flattened API**: All methods directly on `Client` (LaunchDarkly style)
2. **Keyword Arguments**: `**options` for flexibility and readability
3. **Smart Defaults**: `cache_ttl: 60`, `label: "production"`
4. **Graceful Degradation**: Fallback support encouraged, logs instead of raising when fallback provided
5. **Convenience Methods**: `compile_prompt` for common one-step use case
6. **Detail Variants**: `get_prompt_detail` for observability (LaunchDarkly pattern)
7. **Built-in Instrumentation**: ActiveSupport::Notifications for observability

**Observability & Instrumentation:**

```ruby
class Client
  def get_prompt(name, **options)
    start_time = Time.now

    # Fetch logic...
    result = # ...

    # Emit instrumentation event
    instrument('prompt.get', {
      name: name,
      cached: cache_hit?,
      duration_ms: (Time.now - start_time) * 1000,
      version: result.version,
      fallback_used: result.is_fallback
    })

    result
  end

  private

  def instrument(event, payload)
    return unless defined?(ActiveSupport::Notifications)
    ActiveSupport::Notifications.instrument("langfuse.#{event}", payload)
  end
end

# Subscribe to events for monitoring
ActiveSupport::Notifications.subscribe('langfuse.prompt.get') do |name, start, finish, id, payload|
  # Log to stdout
  Rails.logger.info("Langfuse prompt fetch", payload)

  # Send to StatsD/Datadog
  StatsD.increment('langfuse.prompt.get')
  StatsD.timing('langfuse.prompt.duration', payload[:duration_ms])
  StatsD.increment('langfuse.prompt.cache_hit') if payload[:cached]
  StatsD.increment('langfuse.prompt.fallback') if payload[:fallback_used]
end
```

### 4. Langfuse::PromptCache

**Purpose**: Thread-safe in-memory cache with TTL and stale-while-revalidate support.

```ruby
module Langfuse
  class PromptCache
    DEFAULT_TTL_SECONDS = 60
    MAX_CACHE_SIZE = 1000  # Prevent unbounded memory growth

    class CacheItem
      attr_reader :value, :expiry

      def initialize(value, ttl_seconds)
        @value = value
        @expiry = Time.now + ttl_seconds
      end

      def expired?
        Time.now > @expiry
      end
    end

    def initialize(max_size: MAX_CACHE_SIZE)
      @cache = {}
      @mutex = Mutex.new
      @refreshing_keys = {}
      @access_order = []  # Track access for LRU eviction
      @max_size = max_size
    end

    # Get item including expired entries (for stale-while-revalidate)
    # Implements cache stampede protection
    #
    # @param key [String] Cache key
    # @return [CacheItem, nil]
    def get_including_expired(key)
      @mutex.synchronize do
        item = @cache[key]

        # Update access order for LRU
        if item
          @access_order.delete(key)
          @access_order.push(key)
        end

        item
      end
    end

    # Generate cache key from prompt parameters
    #
    # @param name [String] Prompt name
    # @param version [Integer, nil] Version number
    # @param label [String, nil] Label
    # @return [String] Cache key
    #
    # @example
    #   create_key(name: "greeting", label: "production")
    #   # => "greeting-label:production"
    def create_key(name:, version: nil, label: nil)
      parts = [name]
      if version
        parts << "version:#{version}"
      elsif label
        parts << "label:#{label}"
      else
        parts << "label:production"
      end
      parts.join("-")
    end

    # Store value in cache with TTL and LRU eviction
    #
    # @param key [String] Cache key
    # @param value [TextPromptClient, ChatPromptClient] Prompt client
    # @param ttl_seconds [Integer, nil] TTL (default: 60)
    def set(key, value, ttl_seconds = nil)
      ttl = ttl_seconds || DEFAULT_TTL_SECONDS
      @mutex.synchronize do
        # Evict LRU entry if at capacity
        evict_lru if @cache.size >= @max_size && !@cache.key?(key)

        @cache[key] = CacheItem.new(value, ttl)

        # Update access order
        @access_order.delete(key)
        @access_order.push(key)
      end
    end

    # Track background refresh promise
    #
    # @param key [String] Cache key
    # @param promise [Thread] Background refresh thread
    def add_refreshing_promise(key, promise)
      @mutex.synchronize { @refreshing_keys[key] = promise }

      # Non-blocking cleanup after thread completes
      # This ensures stale-while-revalidate doesn't block the calling thread
      Thread.new do
        promise.join
        @mutex.synchronize { @refreshing_keys.delete(key) }
      end
    end

    # Check if key is currently being refreshed
    #
    # @param key [String] Cache key
    # @return [Boolean]
    def refreshing?(key)
      @mutex.synchronize { @refreshing_keys.key?(key) }
    end

    # Invalidate all cache entries for a prompt
    #
    # @param prompt_name [String] Prompt name
    def invalidate(prompt_name)
      @mutex.synchronize do
        @cache.keys.each do |key|
          if key.start_with?(prompt_name)
            @cache.delete(key)
            @access_order.delete(key)
          end
        end
      end
    end

    private

    # Evict least recently used cache entry
    def evict_lru
      return if @access_order.empty?

      lru_key = @access_order.shift
      @cache.delete(lru_key)
    end
  end
end
```

**Key Design Decisions:**

1. **Mutex for Thread Safety**: All cache operations use mutex synchronization
2. **Stale-While-Revalidate**: Return expired cache while refreshing in background
3. **Simple Key Generation**: Deterministic cache keys based on name/version/label
4. **Rails.cache Integration**: Phase 2 will add optional Rails.cache backend

**Alternative Considered: Rails.cache by Default**

We could use `Rails.cache` immediately, but:
- **Pro**: Distributed caching across processes/servers
- **Con**: Requires Rails dependency, slower than in-memory
- **Decision**: Start with in-memory, add Rails.cache as opt-in in Phase 2

**Background Refresh with Thread Pool:**

To prevent unbounded thread creation during cache refreshes, use a thread pool:

```ruby
require 'concurrent-ruby'

class PromptCache
  def initialize(max_size: MAX_CACHE_SIZE)
    @cache = {}
    @mutex = Mutex.new
    @refreshing_keys = {}
    @access_order = []
    @max_size = max_size
    # Thread pool for background refreshes (max 5 concurrent)
    @thread_pool = Concurrent::FixedThreadPool.new(5)
  end

  def trigger_background_refresh(key, &block)
    return if refreshing?(key)

    @mutex.synchronize do
      return if @refreshing_keys.key?(key)

      # Submit to thread pool instead of creating unbounded threads
      future = Concurrent::Future.execute(executor: @thread_pool) do
        block.call
      end

      @refreshing_keys[key] = future

      # Clean up when done (non-blocking)
      future.add_observer do |time, value, reason|
        @mutex.synchronize { @refreshing_keys.delete(key) }
      end
    end
  end
end
```

**Benefits:**
- Limits concurrent API calls to 5 (configurable)
- Prevents thread exhaustion under high load
- Graceful handling of refresh failures

### 5. Langfuse::TextPromptClient

**Purpose**: Represent and manipulate text-based prompts.

```ruby
module Langfuse
  class TextPromptClient
    attr_reader :name, :version, :config, :labels, :tags, :prompt, :type, :is_fallback

    def initialize(response, is_fallback: false)
      @name = response[:name]
      @version = response[:version]
      @config = response[:config] || {}
      @labels = response[:labels] || []
      @tags = response[:tags] || []
      @prompt = response[:prompt]
      @type = :text
      @is_fallback = is_fallback
    end

    # Compile prompt by substituting variables
    #
    # @param variables [Hash] Variable substitutions
    # @return [String] Compiled prompt
    #
    # @example
    #   prompt.compile(name: "Alice", city: "NYC")
    #   # "Hello {{name}} from {{city}}!" => "Hello Alice from NYC!"
    def compile(variables = {})
      Mustache.render(prompt, variables.transform_keys(&:to_s))
    end

    # Convert to LangChain PromptTemplate format
    #
    # @return [String] Prompt with {var} syntax
    #
    # @example
    #   prompt.to_langchain
    #   # "Hello {{name}}!" => "Hello {name}!"
    def to_langchain
      transform_to_langchain_variables(prompt)
    end

    # Serialize to JSON
    #
    # @return [String] JSON representation
    def to_json(*args)
      {
        name: name,
        prompt: prompt,
        version: version,
        is_fallback: is_fallback,
        tags: tags,
        labels: labels,
        type: type,
        config: config
      }.to_json(*args)
    end

    private

    def transform_to_langchain_variables(content)
      # Convert {{var}} to {var}
      content.gsub(/\{\{(\w+)\}\}/, '{\1}')
    end
  end
end
```

**Key Design Decisions:**

1. **Immutable**: All attributes are read-only (Ruby convention for value objects)
2. **Mustache Templating**: Use `mustache` gem for variable substitution
3. **Symbol Keys**: Return `:text` for type (Ruby convention)
4. **Simple Interface**: Focus on common use cases (compile, to_langchain)

### 6. Langfuse::ChatPromptClient

**Purpose**: Represent and manipulate chat-based prompts with placeholder support.

```ruby
module Langfuse
  class ChatPromptClient
    attr_reader :name, :version, :config, :labels, :tags, :prompt, :type, :is_fallback

    # Chat message types
    MESSAGE_TYPE_CHAT = "chatmessage"
    MESSAGE_TYPE_PLACEHOLDER = "placeholder"

    def initialize(response, is_fallback: false)
      @name = response[:name]
      @version = response[:version]
      @config = response[:config] || {}
      @labels = response[:labels] || []
      @tags = response[:tags] || []
      @prompt = normalize_prompt(response[:prompt])
      @type = :chat
      @is_fallback = is_fallback
    end

    # Compile prompt by substituting variables and resolving placeholders
    #
    # @param variables [Hash] Variable substitutions for Mustache templates
    # @param placeholders [Hash] Placeholder resolutions (name => array of messages)
    # @param required_placeholders [Array<String, Symbol>] List of required placeholder names
    # @return [Array<Hash>] Array of chat messages with resolved placeholders
    # @raise [ArgumentError] if required placeholder is missing or invalid
    #
    # @example
    #   messages = prompt.compile(
    #     { user_name: "Alice" },
    #     { examples: [
    #       { role: "user", content: "Hi" },
    #       { role: "assistant", content: "Hello!" }
    #     ]}
    #   )
    def compile(variables = {}, placeholders = {}, required_placeholders: [])
      # Validate required placeholders are provided
      required_placeholders.each do |name|
        unless placeholders.key?(name) || placeholders.key?(name.to_sym) || placeholders.key?(name.to_s)
          raise ArgumentError, "Required placeholder '#{name}' not provided"
        end
      end

      messages = []

      prompt.each do |item|
        if item[:type] == MESSAGE_TYPE_PLACEHOLDER
          # Resolve placeholder
          placeholder_value = placeholders[item[:name].to_sym] || placeholders[item[:name]]

          if placeholder_value.nil?
            # Keep unresolved placeholder for debugging
            messages << item
          elsif placeholder_value.is_a?(Array)
            # Handle empty arrays - skip them
            next if placeholder_value.empty?

            # Validate all messages have proper structure
            unless valid_chat_messages?(placeholder_value)
              raise ArgumentError, "Placeholder '#{item[:name]}' must contain valid chat messages with :role and :content"
            end

            messages.concat(placeholder_value)
          else
            # Invalid placeholder value
            raise ArgumentError, "Placeholder '#{item[:name]}' must be an Array of messages, got #{placeholder_value.class}"
          end
        elsif item[:type] == MESSAGE_TYPE_CHAT
          # Regular message: substitute variables
          messages << {
            role: item[:role],
            content: Mustache.render(item[:content], variables.transform_keys(&:to_s))
          }
        end
      end

      messages
    end

    # Convert to LangChain ChatPromptTemplate format
    #
    # @param placeholders [Hash] Placeholder resolutions
    # @return [Array] Array of messages and MessagesPlaceholder objects
    #
    # @example
    #   langchain_messages = prompt.to_langchain(
    #     placeholders: { examples: [...] }
    #   )
    def to_langchain(placeholders: {})
      messages = []

      prompt.each do |item|
        if item[:type] == MESSAGE_TYPE_PLACEHOLDER
          placeholder_value = placeholders[item[:name].to_sym] || placeholders[item[:name]]

          if placeholder_value.is_a?(Array) && !placeholder_value.empty?
            # Resolved placeholder: add messages with transformed variables
            placeholder_value.each do |msg|
              messages << {
                role: msg[:role],
                content: transform_to_langchain_variables(msg[:content])
              }
            end
          else
            # Unresolved: convert to LangChain MessagesPlaceholder
            messages << ["placeholder", "{#{item[:name]}}"]
          end
        elsif item[:type] == MESSAGE_TYPE_CHAT
          messages << {
            role: item[:role],
            content: transform_to_langchain_variables(item[:content])
          }
        end
      end

      messages
    end

    def to_json(*args)
      {
        name: name,
        prompt: prompt.map { |item|
          if item[:type] == MESSAGE_TYPE_CHAT
            item.except(:type)
          else
            item
          end
        },
        version: version,
        is_fallback: is_fallback,
        tags: tags,
        labels: labels,
        type: type,
        config: config
      }.to_json(*args)
    end

    private

    def normalize_prompt(messages)
      # Ensure all messages have a type field
      messages.map do |item|
        if item[:type]
          item # Already has type
        else
          # Legacy format: add type
          { type: MESSAGE_TYPE_CHAT }.merge(item)
        end
      end
    end

    def transform_to_langchain_variables(content)
      content.gsub(/\{\{(\w+)\}\}/, '{\1}')
    end

    def valid_chat_messages?(messages)
      messages.all? { |m| m.is_a?(Hash) && m.key?(:role) && m.key?(:content) }
    end
  end
end
```

**Key Design Decisions:**

1. **Placeholder Support**: First-class support for dynamic message insertion
2. **Type Normalization**: Handle both legacy and new message formats
3. **Flexible Placeholders**: Accept symbol or string keys for Ruby ergonomics
4. **Array Flattening**: `compile` returns flat array of resolved messages

### 7. Langfuse::ApiClient Extensions

**Purpose**: Add HTTP endpoints for prompt operations.

```ruby
module Langfuse
  class ApiClient
    # ... existing methods ...

    # Fetch a prompt by name
    #
    # @param name [String] Prompt name
    # @param version [Integer, nil] Specific version
    # @param label [String, nil] Label filter
    # @param timeout_seconds [Integer, nil] Request timeout
    #
    # @return [Hash] Prompt response
    # @note Retries are handled by Faraday retry middleware (max: 2, interval: 0.5s)
    def get_prompt(name, version: nil, label: nil, timeout_seconds: nil)
      params = {}
      params[:version] = version if version
      params[:label] = label if label

      response = connection(timeout: timeout_seconds).get("/api/public/v2/prompts/#{name}") do |req|
        req.params = params
      end

      handle_response(response)
    rescue Faraday::Error => e
      raise ApiError, "Failed to fetch prompt '#{name}': #{e.message}"
    end

    # Create a new prompt
    #
    # @param body [Hash] Prompt definition
    # @return [Hash] Created prompt response
    def create_prompt(body)
      response = connection.post("/api/public/v2/prompts") do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = body.to_json
      end

      handle_response(response)
    end

    # Update prompt version labels
    #
    # @param name [String] Prompt name
    # @param version [Integer] Version number
    # @param labels [Array<String>] New labels
    #
    # @return [Hash] Updated prompt
    def update_prompt_version(name, version, labels)
      response = connection.patch("/api/public/v2/prompts/#{name}/#{version}") do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = { labels: labels }.to_json
      end

      handle_response(response)
    end

    private

    def connection(timeout: nil)
      if timeout
        # Create dedicated connection for custom timeout
        # to avoid mutating shared connection
        build_connection(timeout: timeout)
      else
        @connection ||= build_connection
      end
    end

    def build_connection(timeout: nil)
      Faraday.new(
        url: base_url,
        headers: {
          'Authorization' => authorization_header,
          'User-Agent' => "langfuse-ruby/#{Langfuse::VERSION}"
        }
      ) do |conn|
        conn.request :retry, max: 2, interval: 0.5
        conn.response :json, content_type: /\bjson$/
        conn.adapter Faraday.default_adapter
        conn.options.timeout = timeout if timeout
      end
    end

    def authorization_header
      # Basic Auth: base64(public_key:secret_key)
      credentials = "#{@public_key}:#{@secret_key}"
      "Basic #{Base64.strict_encode64(credentials)}"
    end

    def handle_response(response)
      case response.status
      when 200..299
        symbolize_keys(response.body)
      when 401
        raise UnauthorizedError, "Invalid API credentials"
      when 404
        raise NotFoundError, "Prompt not found"
      when 429
        raise RateLimitError, "Rate limit exceeded"
      else
        raise ApiError, "HTTP #{response.status}: #{response.body}"
      end
    end

    def symbolize_keys(hash)
      # Recursively convert string keys to symbols
      JSON.parse(hash.to_json, symbolize_names: true)
    end
  end
end
```

**Key Design Decisions:**

1. **Faraday for HTTP**: Industry standard, flexible middleware
2. **Basic Auth**: Use public_key:secret_key as per Langfuse spec
3. **Automatic Retries**: Built-in exponential backoff for transient errors
4. **Symbol Keys**: Return hashes with symbol keys (Ruby convention)
5. **Custom Exceptions**: Specific errors for different failure modes

---

## API Design

### Client Initialization

```ruby
# Option 1: Global configuration (recommended for Rails)
Langfuse.configure do |config|
  config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
  config.secret_key = ENV['LANGFUSE_SECRET_KEY']
  config.cache_ttl = 120  # 2 minutes
end

# Use global singleton client
client = Langfuse.client

# Option 2: Per-client configuration
config = Langfuse::Config.new do |c|
  c.public_key = "pk_..."
  c.secret_key = "sk_..."
end
client = Langfuse::Client.new(config)

# Option 3: Inline hash (backward compatible)
client = Langfuse::Client.new(
  public_key: "pk_...",
  secret_key: "sk_..."
)
```

### Get Prompt (Flattened API)

```ruby
# Get latest production version
prompt = client.get_prompt("greeting")

# Get specific version
prompt = client.get_prompt("greeting", version: 2)

# Get by label
prompt = client.get_prompt("greeting", label: "staging")

# Disable caching for testing
prompt = client.get_prompt("greeting", cache_ttl: 0)

# With fallback for resilience (RECOMMENDED)
prompt = client.get_prompt("greeting",
  fallback: "Hello {{name}}!",
  type: :text
)

# Chat prompt with fallback
prompt = client.get_prompt("conversation",
  type: :chat,
  fallback: [
    { role: "system", content: "You are a helpful assistant." },
    { role: "user", content: "{{user_message}}" }
  ]
)

# Get with detailed metadata (debugging/observability)
detail = client.get_prompt_detail("greeting")
# => {
#   prompt: TextPromptClient,
#   cached: true,
#   stale: false,
#   version: 3,
#   fetch_time_ms: 1.2,
#   source: :cache
# }
```

### Convenience Method: Compile in One Step

```ruby
# Get and compile in single call
text = client.compile_prompt("greeting",
  variables: { name: "Alice", city: "SF" },
  fallback: "Hello {{name}}!",
  type: :text
)
# => "Hello Alice from SF!"

# Chat prompt compilation
messages = client.compile_prompt("conversation",
  variables: { user_name: "Alice" },
  placeholders: {
    examples: [
      { role: "user", content: "Hi" },
      { role: "assistant", content: "Hello!" }
    ]
  },
  type: :chat
)
```

### Create Prompt

```ruby
# Create text prompt
text_prompt = client.create_prompt(
  name: "greeting",
  prompt: "Hello {{name}} from {{city}}!",
  type: :text,
  labels: ["production"],
  tags: ["customer-facing"],
  config: { temperature: 0.7 }
)

# Create chat prompt
chat_prompt = client.create_prompt(
  name: "conversation",
  type: :chat,
  prompt: [
    { role: "system", content: "You are a helpful assistant." },
    { role: "user", content: "{{user_message}}" }
  ],
  labels: ["staging"]
)

# Create chat prompt with placeholders
chat_prompt = client.create_prompt(
  name: "rag-pipeline",
  type: :chat,
  prompt: [
    { role: "system", content: "You are a helpful assistant." },
    { type: "placeholder", name: "examples" },
    { role: "user", content: "{{user_question}}" }
  ]
)
```

### Update Prompt

```ruby
# Promote version to production
client.update_prompt(
  name: "greeting",
  version: 3,
  labels: ["production", "stable"]
)

# Tag for A/B testing
client.update_prompt(
  name: "greeting",
  version: 4,
  labels: ["experiment-a"]
)
```

### Two-Step: Get + Compile

```ruby
# Text prompt compilation
text_prompt = client.get_prompt("greeting", type: :text)
compiled_text = text_prompt.compile(
  name: "Alice",
  city: "San Francisco"
)
# => "Hello Alice from San Francisco!"

# Chat prompt compilation
chat_prompt = client.get_prompt("conversation", type: :chat)
compiled_messages = chat_prompt.compile(
  { user_name: "Alice" },
  {
    examples: [
      { role: "user", content: "What's the weather?" },
      { role: "assistant", content: "Let me check for you." }
    ]
  }
)
# => [
#   { role: "system", content: "You are a helpful assistant." },
#   { role: "user", content: "What's the weather?" },
#   { role: "assistant", content: "Let me check for you." },
#   { role: "user", content: "Alice's message" }
# ]
```

### LangChain Integration

```ruby
# Text prompt to LangChain
text_prompt = client.prompt.get("greeting", type: :text)
langchain_template = text_prompt.to_langchain
# => "Hello {name} from {city}!"

# Chat prompt to LangChain
chat_prompt = client.prompt.get("conversation", type: :chat)
langchain_messages = chat_prompt.to_langchain
# => [
#   { role: "system", content: "You are a helpful assistant." },
#   ["placeholder", "{examples}"],
#   { role: "user", content: "{user_message}" }
# ]
```

### Ruby Idioms

```ruby
# Graceful error handling with fallback (recommended)
prompt = client.get_prompt("greeting",
  fallback: "Hello {{name}}!",
  type: :text
)
# Always succeeds - returns fallback on error

# Or: Traditional exception handling
begin
  prompt = client.get_prompt("greeting")
rescue Langfuse::NotFoundError => e
  Rails.logger.error("Prompt not found: #{e.message}")
  # Handle error
end

# Rails integration with global client
class AiService
  def initialize
    @langfuse = Langfuse.client  # Global singleton
  end

  def generate_greeting(user)
    # One-step compile with fallback
    text = @langfuse.compile_prompt("greeting",
      variables: { name: user.name, city: user.city },
      fallback: "Hello {{name}} from {{city}}!",
      type: :text
    )

    # Use with OpenAI, Anthropic, etc.
    OpenAI::Client.new.chat(
      parameters: {
        model: "gpt-4",
        messages: [{ role: "user", content: text }]
      }
    )
  end
end
```

---

## Caching Strategy

### Cache Behavior

The caching system implements **stale-while-revalidate** pattern for optimal performance:

```
┌─────────────────────────────────────────────────────────────┐
│              Cache State Transitions                         │
└─────────────────────────────────────────────────────────────┘

[MISS] ──fetch──> [FRESH] ──60s──> [EXPIRED]
                     │                 │
                     │                 │
                     │                 └──background refresh──> [FRESH]
                     │                          │
                     └──────return stale────────┘


State: MISS
- No cache entry exists
- Fetch immediately from API
- Block until response received
- Store in cache with TTL

State: FRESH
- Cache entry exists and not expired
- Return immediately from cache
- No API call made
- Best performance (<1ms)

State: EXPIRED
- Cache entry exists but expired
- Return stale cache immediately
- Trigger background refresh (async)
- Next request will use fresh data
- Ensures fast response times
```

### Cache Key Generation

```ruby
# Format: "name-{version|label}:value"

# Latest production (default)
create_key(name: "greeting")
# => "greeting-label:production"

# Specific version
create_key(name: "greeting", version: 2)
# => "greeting-version:2"

# Specific label
create_key(name: "greeting", label: "staging")
# => "greeting-label:staging"
```

### TTL Configuration

```ruby
# Default TTL: 60 seconds
prompt = client.prompt.get("greeting")

# Custom TTL: 5 minutes
prompt = client.prompt.get("greeting", cache_ttl_seconds: 300)

# Disable caching
prompt = client.prompt.get("greeting", cache_ttl_seconds: 0)

# Very long TTL for stable prompts
prompt = client.prompt.get("greeting", cache_ttl_seconds: 3600)
```

### Thread Safety

All cache operations are thread-safe using `Mutex`:

```ruby
class PromptCache
  def initialize
    @cache = {}
    @mutex = Mutex.new
    @refreshing_keys = {}
  end

  def get_including_expired(key)
    @mutex.synchronize { @cache[key] }
  end

  def set(key, value, ttl)
    @mutex.synchronize do
      @cache[key] = CacheItem.new(value, ttl)
    end
  end

  def refreshing?(key)
    @mutex.synchronize { @refreshing_keys.key?(key) }
  end
end
```

### Invalidation

Cache invalidation happens automatically on updates:

```ruby
# Update prompt labels
client.prompt.update(name: "greeting", version: 3, labels: ["production"])

# Cache automatically invalidated
# All keys starting with "greeting" are removed
# Next get("greeting") will fetch fresh data
```

### Rails.cache Integration (Phase 2)

```ruby
# Opt-in to distributed caching
Langfuse.configure do |config|
  config.cache_backend = :rails
  config.cache_namespace = "langfuse_prompts"
end

# Implementation
class PromptCache
  def initialize(backend: :memory)
    @backend = backend
    @cache = backend == :rails ? Rails.cache : {}
    @mutex = Mutex.new unless backend == :rails
  end

  def get_including_expired(key)
    if @backend == :rails
      Rails.cache.read(cache_key(key))
    else
      @mutex.synchronize { @cache[key] }
    end
  end

  private

  def cache_key(key)
    "#{Langfuse.configuration.cache_namespace}:#{key}"
  end
end
```

**Trade-off: In-memory vs Rails.cache**

| Aspect | In-memory | Rails.cache |
|--------|-----------|-------------|
| Speed | 0.01ms | 1-10ms (Redis) |
| Shared across processes | No | Yes |
| Memory usage | Per-process | Shared |
| Ideal for | Single-server | Multi-server |
| Default | ✓ Phase 1 | Phase 2 option |

---

## REST API Integration

### Langfuse API Endpoints

```
Base URL: https://cloud.langfuse.com
Authentication: Basic Auth (public_key:secret_key)

GET    /api/public/v2/prompts/{name}
       ?version={version}
       &label={label}

POST   /api/public/v2/prompts

PATCH  /api/public/v2/prompts/{name}/{version}
```

### HTTP Client: Faraday

**Why Faraday?**

1. **Industry Standard**: Most popular Ruby HTTP client
2. **Middleware Support**: Easy to add logging, instrumentation
3. **Adapter Agnostic**: Works with Net::HTTP, Patron, HTTPClient
4. **Built-in Retry**: Exponential backoff for transient errors
5. **Already Used**: Likely in Gemfile for other integrations

**Alternative Considered: HTTParty**

- Simpler API, but less flexible
- No built-in retry middleware
- Harder to instrument for observability

### Request/Response Handling

```ruby
# GET Prompt
GET /api/public/v2/prompts/greeting?label=production

Response 200 OK:
{
  "name": "greeting",
  "version": 3,
  "type": "text",
  "prompt": "Hello {{name}}!",
  "config": { "temperature": 0.7 },
  "labels": ["production"],
  "tags": ["customer-facing"],
  "createdAt": "2025-01-01T00:00:00Z",
  "updatedAt": "2025-01-15T00:00:00Z"
}

# CREATE Prompt
POST /api/public/v2/prompts
Content-Type: application/json

{
  "name": "greeting",
  "type": "text",
  "prompt": "Hello {{name}}!",
  "labels": ["staging"],
  "config": {}
}

Response 201 Created:
{
  "name": "greeting",
  "version": 1,
  ...
}

# UPDATE Prompt
PATCH /api/public/v2/prompts/greeting/3
Content-Type: application/json

{
  "labels": ["production", "stable"]
}

Response 200 OK:
{
  "name": "greeting",
  "version": 3,
  "labels": ["production", "stable"],
  ...
}
```

### Error Handling

```ruby
module Langfuse
  class Error < StandardError; end
  class ApiError < Error; end
  class UnauthorizedError < ApiError; end
  class NotFoundError < ApiError; end
  class RateLimitError < ApiError; end
  class TimeoutError < ApiError; end

  class ApiClient
    def handle_response(response)
      case response.status
      when 200..299
        symbolize_keys(response.body)
      when 401
        raise UnauthorizedError, "Invalid API credentials"
      when 404
        raise NotFoundError, "Resource not found: #{response.body}"
      when 429
        raise RateLimitError, "Rate limit exceeded. Retry after: #{response.headers['Retry-After']}"
      when 500..599
        raise ApiError, "Server error: #{response.status}"
      else
        raise ApiError, "Unexpected response: #{response.status}"
      end
    end
  end
end
```

### Retry Logic

```ruby
# Faraday retry middleware configuration
connection = Faraday.new do |conn|
  conn.request :retry,
    max: 2,
    interval: 0.5,
    interval_randomness: 0.5,
    backoff_factor: 2,
    retry_statuses: [429, 500, 502, 503, 504],
    retry_if: ->(env, exception) {
      # Retry on network errors
      exception.is_a?(Faraday::TimeoutError) ||
      exception.is_a?(Faraday::ConnectionFailed)
    }
end

# Exponential backoff:
# Attempt 1: immediate
# Attempt 2: 0.5s + random(0-0.25s)
# Attempt 3: 1.0s + random(0-0.5s)
```

### Authentication

```ruby
# Basic Auth implementation
class ApiClient
  def initialize(public_key:, secret_key:, base_url:)
    @public_key = public_key
    @secret_key = secret_key
    @base_url = base_url
  end

  private

  def authorization_header
    credentials = "#{@public_key}:#{@secret_key}"
    "Basic #{Base64.strict_encode64(credentials)}"
  end

  def connection
    @connection ||= Faraday.new(
      url: @base_url,
      headers: {
        'Authorization' => authorization_header,
        'User-Agent' => "langfuse-ruby/#{Langfuse::VERSION}",
        'Content-Type' => 'application/json'
      }
    )
  end
end
```

### Timeout Configuration

```ruby
# Default timeout: 5 seconds
client = Langfuse::Client.new(timeout: 5)

# Per-request timeout override
prompt = client.prompt.get(
  "greeting",
  fetch_timeout_ms: 2000  # 2 second timeout
)

# Implementation
def get_prompt(name, timeout_seconds: nil, **options)
  conn = connection.dup
  conn.options.timeout = timeout_seconds if timeout_seconds

  response = conn.get("/api/public/v2/prompts/#{name}") do |req|
    req.params = options
  end

  handle_response(response)
rescue Faraday::TimeoutError => e
  raise Langfuse::TimeoutError, "Request timed out after #{timeout_seconds}s"
end
```

---

## Variable Substitution

### Templating Engine: Mustache

**Why Mustache?**

1. **Logic-less**: Simple, secure, no arbitrary code execution
2. **Cross-language**: Same syntax as JavaScript SDK (consistency)
3. **Ruby Gem**: Well-maintained `mustache` gem available
4. **Familiar**: Widely used in Rails ecosystem

**Alternative Considered: ERB**

- Pro: Built into Ruby stdlib
- Con: Allows Ruby code execution (security risk)
- Con: Different syntax than JS SDK (inconsistent)

### Text Prompt Compilation

```ruby
# Template
"Hello {{name}} from {{city}}!"

# Variables
{ name: "Alice", city: "San Francisco" }

# Compiled
"Hello Alice from San Francisco!"

# Implementation
def compile(variables = {})
  # Mustache expects string keys
  Mustache.render(prompt, variables.transform_keys(&:to_s))
end
```

### Chat Prompt Compilation

```ruby
# Template
[
  { role: "system", content: "You are helping {{user_name}}." },
  { type: "placeholder", name: "examples" },
  { role: "user", content: "{{user_question}}" }
]

# Variables + Placeholders
variables = { user_name: "Alice", user_question: "What's the weather?" }
placeholders = {
  examples: [
    { role: "user", content: "How are you?" },
    { role: "assistant", content: "I'm great!" }
  ]
}

# Compiled
[
  { role: "system", content: "You are helping Alice." },
  { role: "user", content: "How are you?" },
  { role: "assistant", content: "I'm great!" },
  { role: "user", content: "What's the weather?" }
]
```

### Placeholder Resolution

```ruby
def compile(variables = {}, placeholders = {})
  messages = []

  prompt.each do |item|
    case item[:type]
    when MESSAGE_TYPE_PLACEHOLDER
      # Resolve placeholder
      name = item[:name]
      value = placeholders[name.to_sym] || placeholders[name]

      if valid_messages?(value)
        # Flatten array of messages
        messages.concat(value)
      elsif value.nil?
        # Keep unresolved for debugging
        messages << item
      else
        # Invalid type: stringify
        messages << { role: "system", content: value.to_s }
      end

    when MESSAGE_TYPE_CHAT
      # Regular message: apply Mustache
      messages << {
        role: item[:role],
        content: Mustache.render(item[:content], variables.transform_keys(&:to_s))
      }
    end
  end

  messages
end

def valid_messages?(value)
  value.is_a?(Array) &&
    value.all? { |m| m.is_a?(Hash) && m.key?(:role) && m.key?(:content) }
end
```

### Escaping and Security

```ruby
# Mustache escapes HTML by default
# Disable escaping for plain text
Mustache.escape = ->(text) { text }

# Or use triple mustache for unescaped
"Hello {{{user_input}}}!"  # No escaping

# For chat prompts, always sanitize user input in variables
def compile(variables = {}, placeholders = {})
  # Sanitize string values to prevent injection and limit payload size
  safe_variables = variables.transform_values do |v|
    v.is_a?(String) ? sanitize(v) : v
  end

  # ... compilation logic
end

# Sanitize input to prevent control character injection and DoS attacks
#
# @param text [String] Input text to sanitize
# @param max_length [Integer] Maximum allowed length (default: 10,000)
# @return [String] Sanitized text
#
# Rationale for 10,000 char limit:
# - Most LLM prompts are <5K tokens (~20K chars)
# - Prevents memory exhaustion attacks
# - Large enough for legitimate use cases
# - Configurable via parameter if needed
def sanitize(text, max_length: 10_000)
  # Remove control characters (null bytes, escape sequences, etc.)
  sanitized = text.gsub(/[\x00-\x1F\x7F]/, '')

  # Truncate to prevent DoS
  sanitized.length > max_length ? sanitized[0...max_length] : sanitized
end
```

### LangChain Variable Transformation

```ruby
# Langfuse format: {{variable}}
# LangChain format: {variable}

def transform_to_langchain_variables(content)
  # Simple regex replacement
  content.gsub(/\{\{(\w+)\}\}/, '{\1}')
end

# Example
transform_to_langchain_variables("Hello {{name}} from {{city}}!")
# => "Hello {name} from {city}!"
```

### Edge Cases

```ruby
# Empty variables
prompt.compile({})
# => "Hello {{name}}!"  (unchanged)

# Missing variables
prompt.compile(name: "Alice")
# => "Hello Alice from {{city}}!"

# Extra variables
prompt.compile(name: "Alice", city: "SF", unused: "value")
# => "Hello Alice from SF!" (unused ignored)

# Nil values
prompt.compile(name: nil)
# => "Hello  from {{city}}!"

# Nested objects (not supported)
prompt.compile(user: { name: "Alice" })
# => "Hello {{name}}!"  (no nested access)
```

---

## Implementation Phases

### Phase 1: Core Functionality (MVP)

**Goal**: Basic prompt retrieval and caching

**Scope**:
- `PromptManager#get` with caching
- `TextPromptClient` with `compile`
- `ChatPromptClient` with `compile`
- `PromptCache` (in-memory)
- `ApiClient` extensions for GET /prompts

**Deliverables**:
- [ ] `Langfuse::PromptManager` class
- [ ] `Langfuse::TextPromptClient` class
- [ ] `Langfuse::ChatPromptClient` class
- [ ] `Langfuse::PromptCache` class
- [ ] `ApiClient#get_prompt` method
- [ ] Basic error handling
- [ ] Unit tests (>90% coverage)
- [ ] Integration tests with VCR
- [ ] Documentation and examples

**Success Criteria**:
- Can fetch and cache prompts
- Can compile text and chat prompts
- Thread-safe for Rails apps
- <100ms cache hit latency

**Estimated Effort**: 3-4 days (includes buffer for edge cases and thorough testing)

---

### Phase 2: Advanced Features

**Goal**: Prompt creation, updates, and advanced caching

**Scope**:
- `PromptManager#create`
- `PromptManager#update`
- Placeholder support for chat prompts
- Rails.cache backend option
- Cache invalidation on updates

**Deliverables**:
- [ ] `ApiClient#create_prompt` method
- [ ] `ApiClient#update_prompt_version` method
- [ ] Placeholder compilation in `ChatPromptClient`
- [ ] Rails.cache adapter
- [ ] Configuration for cache backend
- [ ] Additional tests for new features

**Success Criteria**:
- Can create and update prompts
- Placeholders work correctly
- Rails.cache integration functional
- No breaking changes

**Estimated Effort**: 2-3 days

---

### Phase 3: LangChain Integration

**Goal**: Seamless LangChain compatibility

**Scope**:
- `TextPromptClient#to_langchain`
- `ChatPromptClient#to_langchain`
- LangChain MessagesPlaceholder format
- Variable syntax transformation

**Deliverables**:
- [ ] LangChain format conversion methods
- [ ] Tests for LangChain compatibility
- [ ] Documentation with LangChain examples

**Success Criteria**:
- Outputs work with langchain-ruby gem
- Variable syntax correctly transformed
- Placeholders converted to MessagesPlaceholder

**Estimated Effort**: 1 day

---

### Phase 4: Polish and Optimization

**Goal**: Production-ready quality

**Scope**:
- Performance optimization
- Enhanced error messages
- Observability hooks
- Comprehensive documentation

**Deliverables**:
- [ ] Benchmarks and performance tests
- [ ] Instrumentation for monitoring (StatsD, Datadog)
- [ ] Detailed error messages with remediation hints
- [ ] Complete API documentation
- [ ] Migration guide from manual prompt management

**Success Criteria**:
- <10ms p95 latency for cache hits
- Comprehensive error messages
- Full documentation coverage

**Estimated Effort**: 2-3 days (comprehensive observability and documentation)

---

### Total Implementation Timeline

**Estimated Total**: 8-11 days (2-2.5 weeks with 30% contingency buffer)

**Phases can be deployed incrementally:**
1. Phase 1 → Beta release for early adopters
2. Phase 2 → Feature-complete release
3. Phase 3 → LangChain integration (optional)
4. Phase 4 → Production-ready v1.0

---

## Testing Strategy

### Unit Tests

**Coverage Target**: >90%

```ruby
# spec/langfuse/prompt_manager_spec.rb
RSpec.describe Langfuse::PromptManager do
  let(:api_client) { instance_double(Langfuse::ApiClient) }
  let(:manager) { described_class.new(api_client: api_client) }

  describe "#get" do
    context "with cache miss" do
      it "fetches from API and caches result" do
        allow(api_client).to receive(:get_prompt).and_return(prompt_response)

        prompt = manager.get("greeting")

        expect(prompt).to be_a(Langfuse::TextPromptClient)
        expect(prompt.name).to eq("greeting")
        expect(api_client).to have_received(:get_prompt).once
      end
    end

    context "with cache hit" do
      it "returns cached prompt without API call" do
        manager.get("greeting")  # Prime cache

        prompt = manager.get("greeting")

        expect(api_client).to have_received(:get_prompt).once  # Only first call
      end
    end

    context "with expired cache" do
      it "returns stale cache and refreshes in background" do
        # Test stale-while-revalidate
      end
    end

    context "with fallback" do
      it "returns fallback on API error" do
        allow(api_client).to receive(:get_prompt).and_raise(Langfuse::ApiError)

        prompt = manager.get("greeting", fallback: "Hello!", type: :text)

        expect(prompt.is_fallback).to be true
        expect(prompt.prompt).to eq("Hello!")
      end
    end
  end

  describe "#create" do
    it "creates text prompt and returns client" do
      allow(api_client).to receive(:create_prompt).and_return(created_response)

      prompt = manager.create(
        name: "greeting",
        prompt: "Hello {{name}}!",
        type: :text
      )

      expect(prompt).to be_a(Langfuse::TextPromptClient)
    end
  end

  describe "#update" do
    it "updates labels and invalidates cache" do
      manager.get("greeting")  # Prime cache

      manager.update(name: "greeting", version: 1, labels: ["production"])

      # Cache should be invalidated
      expect(manager.cache.get_including_expired("greeting-label:production")).to be_nil
    end
  end
end

# spec/langfuse/text_prompt_client_spec.rb
RSpec.describe Langfuse::TextPromptClient do
  let(:response) do
    {
      name: "greeting",
      version: 1,
      type: "text",
      prompt: "Hello {{name}} from {{city}}!",
      config: {},
      labels: ["production"],
      tags: []
    }
  end
  let(:client) { described_class.new(response) }

  describe "#compile" do
    it "substitutes variables" do
      result = client.compile(name: "Alice", city: "SF")
      expect(result).to eq("Hello Alice from SF!")
    end

    it "handles missing variables" do
      result = client.compile(name: "Alice")
      expect(result).to eq("Hello Alice from {{city}}!")
    end

    it "accepts string keys" do
      result = client.compile("name" => "Alice", "city" => "SF")
      expect(result).to eq("Hello Alice from SF!")
    end
  end

  describe "#to_langchain" do
    it "transforms mustache to langchain syntax" do
      result = client.to_langchain
      expect(result).to eq("Hello {name} from {city}!")
    end
  end

  describe "#to_json" do
    it "serializes to JSON" do
      json = JSON.parse(client.to_json)
      expect(json["name"]).to eq("greeting")
      expect(json["type"]).to eq("text")
    end
  end
end

# spec/langfuse/chat_prompt_client_spec.rb
RSpec.describe Langfuse::ChatPromptClient do
  let(:response) do
    {
      name: "conversation",
      version: 1,
      type: "chat",
      prompt: [
        { type: "chatmessage", role: "system", content: "You are {{role}}." },
        { type: "placeholder", name: "examples" },
        { type: "chatmessage", role: "user", content: "{{question}}" }
      ],
      config: {},
      labels: [],
      tags: []
    }
  end
  let(:client) { described_class.new(response) }

  describe "#compile" do
    it "substitutes variables and resolves placeholders" do
      result = client.compile(
        { role: "a helper", question: "What?" },
        {
          examples: [
            { role: "user", content: "Hi" },
            { role: "assistant", content: "Hello!" }
          ]
        }
      )

      expect(result).to eq([
        { role: "system", content: "You are a helper." },
        { role: "user", content: "Hi" },
        { role: "assistant", content: "Hello!" },
        { role: "user", content: "What?" }
      ])
    end

    it "keeps unresolved placeholders" do
      result = client.compile({ role: "a helper", question: "What?" })

      expect(result[1]).to eq({ type: "placeholder", name: "examples" })
    end
  end

  describe "#to_langchain" do
    it "converts to langchain format" do
      result = client.to_langchain

      expect(result).to eq([
        { role: "system", content: "You are {role}." },
        ["placeholder", "{examples}"],
        { role: "user", content: "{question}" }
      ])
    end
  end
end

# spec/langfuse/prompt_cache_spec.rb
RSpec.describe Langfuse::PromptCache do
  let(:cache) { described_class.new }
  let(:prompt) { instance_double(Langfuse::TextPromptClient) }

  describe "#set and #get_including_expired" do
    it "stores and retrieves values" do
      cache.set("key", prompt, 60)

      item = cache.get_including_expired("key")

      expect(item.value).to eq(prompt)
      expect(item.expired?).to be false
    end

    it "marks items as expired after TTL" do
      cache.set("key", prompt, 0)  # Immediate expiry

      sleep 0.01
      item = cache.get_including_expired("key")

      expect(item.expired?).to be true
      expect(item.value).to eq(prompt)  # Still returns value
    end
  end

  describe "#create_key" do
    it "generates key with default label" do
      key = cache.create_key(name: "greeting")
      expect(key).to eq("greeting-label:production")
    end

    it "generates key with version" do
      key = cache.create_key(name: "greeting", version: 2)
      expect(key).to eq("greeting-version:2")
    end

    it "generates key with custom label" do
      key = cache.create_key(name: "greeting", label: "staging")
      expect(key).to eq("greeting-label:staging")
    end
  end

  describe "#invalidate" do
    it "removes all keys for prompt name" do
      cache.set("greeting-label:production", prompt, 60)
      cache.set("greeting-version:2", prompt, 60)
      cache.set("other-label:production", prompt, 60)

      cache.invalidate("greeting")

      expect(cache.get_including_expired("greeting-label:production")).to be_nil
      expect(cache.get_including_expired("greeting-version:2")).to be_nil
      expect(cache.get_including_expired("other-label:production")).not_to be_nil
    end
  end

  describe "thread safety" do
    it "handles concurrent access" do
      threads = 10.times.map do
        Thread.new do
          100.times { |i| cache.set("key-#{i}", prompt, 60) }
        end
      end

      threads.each(&:join)

      # Should not raise or corrupt data
      expect(cache.get_including_expired("key-0")).not_to be_nil
    end
  end

  describe "cache stampede protection" do
    it "prevents duplicate background refreshes" do
      # Simulate 100 threads hitting expired cache simultaneously
      expired_key = "expired-prompt"
      cache.set(expired_key, prompt, 0) # Immediately expired
      sleep 0.01

      refresh_count = Concurrent::AtomicFixnum.new(0)
      allow(manager).to receive(:fetch_and_cache) do
        refresh_count.increment
      end

      threads = 100.times.map do
        Thread.new { manager.get("expired-prompt") }
      end

      threads.each(&:join)

      # Should only trigger 1 background refresh, not 100
      expect(refresh_count.value).to eq(1)
    end
  end

  describe "cache expiry edge cases" do
    it "handles expiry exactly at read time" do
      cache.set("key", prompt, 0.1) # 100ms TTL
      sleep 0.1 # Expire exactly now

      item = cache.get_including_expired("key")
      expect(item).not_to be_nil
      expect(item.expired?).to be true
    end
  end

  describe "LRU eviction" do
    it "evicts least recently used when at capacity" do
      small_cache = described_class.new(max_size: 3)

      # Fill cache
      small_cache.set("key1", prompt, 60)
      small_cache.set("key2", prompt, 60)
      small_cache.set("key3", prompt, 60)

      # Access key1 to make it recently used
      small_cache.get_including_expired("key1")

      # Add key4 - should evict key2 (LRU)
      small_cache.set("key4", prompt, 60)

      expect(small_cache.get_including_expired("key1")).not_to be_nil
      expect(small_cache.get_including_expired("key2")).to be_nil
      expect(small_cache.get_including_expired("key3")).not_to be_nil
      expect(small_cache.get_including_expired("key4")).not_to be_nil
    end
  end
end
```

### Integration Tests with VCR

```ruby
# spec/integration/prompt_manager_integration_spec.rb
RSpec.describe "Prompt Manager Integration", vcr: true do
  let(:client) do
    Langfuse::Client.new(
      public_key: ENV["LANGFUSE_PUBLIC_KEY"],
      secret_key: ENV["LANGFUSE_SECRET_KEY"],
      base_url: "https://cloud.langfuse.com"
    )
  end

  describe "fetching prompts" do
    it "retrieves text prompt from API", vcr: { cassette_name: "get_text_prompt" } do
      prompt = client.prompt.get("greeting")

      expect(prompt).to be_a(Langfuse::TextPromptClient)
      expect(prompt.name).to eq("greeting")
      expect(prompt.version).to be > 0
    end

    it "retrieves chat prompt from API", vcr: { cassette_name: "get_chat_prompt" } do
      prompt = client.prompt.get("conversation", type: :chat)

      expect(prompt).to be_a(Langfuse::ChatPromptClient)
      expect(prompt.prompt).to be_an(Array)
    end
  end

  describe "creating prompts" do
    it "creates new text prompt", vcr: { cassette_name: "create_text_prompt" } do
      prompt = client.prompt.create(
        name: "test-#{SecureRandom.hex(4)}",
        prompt: "Test {{variable}}",
        type: :text
      )

      expect(prompt.version).to eq(1)
    end
  end

  describe "updating prompts" do
    it "updates prompt labels", vcr: { cassette_name: "update_prompt" } do
      result = client.prompt.update(
        name: "greeting",
        version: 1,
        labels: ["test"]
      )

      expect(result[:labels]).to include("test")
    end
  end
end
```

### Performance Tests

```ruby
# spec/performance/caching_performance_spec.rb
RSpec.describe "Caching Performance" do
  let(:manager) { Langfuse::PromptManager.new(api_client: api_client) }
  let(:api_client) { instance_double(Langfuse::ApiClient) }

  before do
    allow(api_client).to receive(:get_prompt).and_return(prompt_response)
  end

  it "cache hits are <1ms" do
    manager.get("greeting")  # Prime cache

    time = Benchmark.realtime do
      100.times { manager.get("greeting") }
    end

    avg_time = (time / 100) * 1000  # Convert to ms
    expect(avg_time).to be < 1
  end

  it "handles 1000 concurrent requests" do
    threads = 1000.times.map do
      Thread.new { manager.get("greeting") }
    end

    expect { threads.each(&:join) }.not_to raise_error
  end
end
```

### Test Coverage Requirements

| Component | Coverage Target |
|-----------|----------------|
| PromptManager | >95% |
| TextPromptClient | >95% |
| ChatPromptClient | >95% |
| PromptCache | >95% |
| ApiClient | >90% |
| **Overall** | **>90%** |

---

## Dependencies

### Required Gems

```ruby
# langfuse-ruby.gemspec
Gem::Specification.new do |spec|
  spec.name = "langfuse-ruby"
  spec.version = "0.2.0"
  spec.authors = ["Langfuse"]
  spec.summary = "Ruby SDK for Langfuse"

  # Runtime dependencies
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-retry", "~> 2.0"
  spec.add_dependency "mustache", "~> 1.1"
  spec.add_dependency "concurrent-ruby", "~> 1.2"

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "vcr", "~> 6.1"
  spec.add_development_dependency "webmock", "~> 3.18"
  spec.add_development_dependency "rubocop", "~> 1.50"
  spec.add_development_dependency "simplecov", "~> 0.22"
end
```

### Dependency Justification

| Gem | Purpose | Why? |
|-----|---------|------|
| `faraday` | HTTP client | Industry standard, flexible, middleware support |
| `faraday-retry` | Retry logic | Exponential backoff, transient error handling |
| `mustache` | Templating | Logic-less, same as JS SDK, security |
| `concurrent-ruby` | Thread pool | Bounded concurrency for background refreshes, prevents thread exhaustion |
| `rspec` | Testing | Ruby standard, readable syntax |
| `vcr` | HTTP recording | Record real API responses for tests |
| `webmock` | HTTP stubbing | Mock HTTP for isolated tests |
| `rubocop` | Linting | Code quality, style enforcement |
| `simplecov` | Coverage | Track test coverage metrics |

### Optional Dependencies

```ruby
# Optional: Rails integration for testing
spec.add_development_dependency "rails", ">= 6.0" if ENV["RAILS_VERSION"]
```

### Version Constraints

- **Ruby**: >= 2.7 (modern syntax, better performance)
- **Faraday**: ~> 2.0 (latest stable, HTTP/2 support)
- **Mustache**: ~> 1.1 (last updated 2016, but stable and widely used; logic-less design means few updates needed)
- **Concurrent-Ruby**: ~> 1.2 (actively maintained, production-ready thread primitives)

### Gemfile.lock Considerations

- Pin exact versions in CI for reproducibility
- Use pessimistic versioning (`~>`) for flexibility
- Test against multiple Ruby versions (2.7, 3.0, 3.1, 3.2)

---

## Code Examples

### Basic Usage

```ruby
require "langfuse"

# Configure globally
Langfuse.configure do |config|
  config.public_key = ENV["LANGFUSE_PUBLIC_KEY"]
  config.secret_key = ENV["LANGFUSE_SECRET_KEY"]
end

# Get global client
client = Langfuse.client

# Get a text prompt (two-step)
prompt = client.get_prompt("greeting")
compiled = prompt.compile(name: "Alice", city: "San Francisco")
puts compiled
# => "Hello Alice from San Francisco!"

# Or: One-step convenience method
text = client.compile_prompt("greeting",
  variables: { name: "Alice", city: "San Francisco" }
)
puts text

# Get a chat prompt
chat_prompt = client.get_prompt("conversation", type: :chat)
messages = chat_prompt.compile(
  { user_name: "Alice" },
  {
    history: [
      { role: "user", content: "Hi!" },
      { role: "assistant", content: "Hello!" }
    ]
  }
)
```

### Rails Integration

```ruby
# config/initializers/langfuse.rb
Langfuse.configure do |config|
  config.public_key = ENV["LANGFUSE_PUBLIC_KEY"]
  config.secret_key = ENV["LANGFUSE_SECRET_KEY"]
  config.base_url = ENV.fetch("LANGFUSE_BASE_URL", "https://cloud.langfuse.com")
  config.cache_ttl = 120  # 2 minutes
  config.logger = Rails.logger
end

# app/services/ai_greeting_service.rb
class AiGreetingService
  def initialize
    @langfuse = Langfuse.client  # Global singleton
  end

  def generate_greeting(user)
    # Fetch and compile in one step with fallback
    compiled = @langfuse.compile_prompt("user-greeting",
      variables: {
        name: user.name,
        city: user.city,
        subscription: user.subscription_tier
      },
      fallback: "Hello {{name}}!",
      type: :text
    )

    # Get prompt config for temperature
    prompt = @langfuse.get_prompt("user-greeting")
    temperature = prompt.config[:temperature] || 0.7

    # Call OpenAI
    response = openai_client.chat(
      parameters: {
        model: "gpt-4",
        messages: [{ role: "user", content: compiled }],
        temperature: temperature
      }
    )

    # Trace with Langfuse
    @langfuse.trace(name: "greeting-generation") do |trace|
      trace.generation(
        name: "openai-call",
        input: compiled,
        output: response.dig("choices", 0, "message", "content"),
        model: "gpt-4",
        metadata: { user_id: user.id }
      )
    end

    response.dig("choices", 0, "message", "content")
  end

  private

  def openai_client
    @openai_client ||= OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
  end
end
```

### Chat Prompt with Placeholders

```ruby
# Create a RAG prompt with placeholders
client.create_prompt(
  name: "rag-qa",
  type: :chat,
  prompt: [
    {
      role: "system",
      content: "You are a helpful assistant. Use the context to answer questions."
    },
    {
      type: "placeholder",
      name: "context_documents"
    },
    {
      role: "user",
      content: "{{user_question}}"
    }
  ],
  labels: ["production"]
)

# Later: compile with dynamic context (two-step)
prompt = client.get_prompt("rag-qa", type: :chat)
messages = prompt.compile(
  { user_question: "What is the capital of France?" },
  {
    context_documents: [
      { role: "system", content: "Context: France is a country in Europe." },
      { role: "system", content: "Context: Paris is the capital of France." }
    ]
  }
)

# Or: compile in one step
messages = client.compile_prompt("rag-qa",
  variables: { user_question: "What is the capital of France?" },
  placeholders: {
    context_documents: [
      { role: "system", content: "Context: France is a country in Europe." },
      { role: "system", content: "Context: Paris is the capital of France." }
    ]
  },
  type: :chat
)

# Result:
# [
#   { role: "system", content: "You are a helpful assistant..." },
#   { role: "system", content: "Context: France is a country..." },
#   { role: "system", content: "Context: Paris is the capital..." },
#   { role: "user", content: "What is the capital of France?" }
# ]
```

### Error Handling

```ruby
# Graceful degradation with fallback (RECOMMENDED)
# Never raises - returns fallback on any error
prompt = client.get_prompt("greeting",
  fallback: "Hello {{name}}!",
  type: :text
)

# Traditional exception handling
begin
  prompt = client.get_prompt("greeting")
rescue Langfuse::NotFoundError => e
  Rails.logger.error("Prompt not found: #{e.message}")
  # Fallback logic here
rescue Langfuse::ApiError => e
  Rails.logger.error("Langfuse API error: #{e.message}")
  # Handle error
end

# Retry with exponential backoff
require "retryable"

Retryable.retryable(
  tries: 3,
  on: [Langfuse::TimeoutError, Langfuse::RateLimitError],
  sleep: ->(n) { 2**n }  # 2s, 4s, 8s
) do
  prompt = client.get_prompt("greeting")
end
```

### Testing with Mocks

```ruby
# spec/services/ai_greeting_service_spec.rb
RSpec.describe AiGreetingService do
  let(:langfuse_client) { instance_double(Langfuse::Client) }
  let(:prompt) do
    instance_double(
      Langfuse::TextPromptClient,
      compile: "Hello Alice from SF!",
      config: { temperature: 0.7 }
    )
  end

  before do
    # Mock global client
    allow(Langfuse).to receive(:client).and_return(langfuse_client)

    # Mock compile_prompt for one-step usage
    allow(langfuse_client).to receive(:compile_prompt)
      .and_return("Hello Alice from SF!")

    # Mock get_prompt for two-step usage
    allow(langfuse_client).to receive(:get_prompt).and_return(prompt)
  end

  it "generates personalized greeting" do
    service = described_class.new
    user = create(:user, name: "Alice", city: "SF")

    greeting = service.generate_greeting(user)

    expect(greeting).to be_present
    expect(langfuse_client).to have_received(:compile_prompt)
      .with("user-greeting", hash_including(variables: hash_including(name: "Alice")))
  end
end
```

### LangChain Integration

```ruby
require "langchain"

# Fetch prompt from Langfuse
prompt = client.prompt.get("greeting", type: :text)

# Convert to LangChain format
langchain_template = prompt.to_langchain
# => "Hello {name} from {city}!"

# Use with LangChain
llm = Langchain::LLM::OpenAI.new(api_key: ENV["OPENAI_API_KEY"])
prompt_template = Langchain::Prompt::PromptTemplate.new(
  template: langchain_template,
  input_variables: ["name", "city"]
)

result = llm.complete(
  prompt: prompt_template.format(name: "Alice", city: "SF")
)

# Chat prompts with LangChain
chat_prompt = client.prompt.get("conversation", type: :chat)
langchain_messages = chat_prompt.to_langchain(
  placeholders: {
    history: [
      { role: "user", content: "Hi" },
      { role: "assistant", content: "Hello!" }
    ]
  }
)

# Use with ChatOpenAI
chat_model = Langchain::LLM::OpenAIChat.new(api_key: ENV["OPENAI_API_KEY"])
response = chat_model.chat(messages: langchain_messages)
```

---

## Migration Strategy

### For Existing Langfuse Users

**Before (Manual Prompt Management)**:

```ruby
# Hardcoded prompts
def greeting_prompt(user)
  "Hello #{user.name}! Welcome to our service."
end

# Or: stored in database
class Prompt < ApplicationRecord
  def compile(variables)
    content.gsub(/\{\{(\w+)\}\}/) { variables[$1.to_sym] }
  end
end
```

**After (Langfuse Prompt Management)**:

```ruby
# Centralized in Langfuse
def greeting_prompt(user)
  # Option 1: Two-step
  prompt = @langfuse.get_prompt("user-greeting")
  prompt.compile(name: user.name, tier: user.tier)

  # Option 2: One-step with fallback
  @langfuse.compile_prompt("user-greeting",
    variables: { name: user.name, tier: user.tier },
    fallback: "Hello {{name}}!",
    type: :text
  )
end
```

### Migration Steps

1. **Install Updated Gem**:
   ```ruby
   # Gemfile
   gem "langfuse-ruby", "~> 0.2.0"
   ```

2. **Add Global Configuration**:
   ```ruby
   # config/initializers/langfuse.rb
   Langfuse.configure do |config|
     config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
     config.secret_key = ENV['LANGFUSE_SECRET_KEY']
     config.cache_ttl = 120
     config.logger = Rails.logger
   end
   ```

3. **Create Prompts in Langfuse**:
   ```ruby
   # scripts/migrate_prompts.rb
   client = Langfuse.client

   # Migrate each hardcoded prompt
   client.create_prompt(
     name: "user-greeting",
     prompt: "Hello {{name}}! Welcome to {{tier}} tier.",
     type: :text,
     labels: ["production"]
   )
   ```

4. **Update Application Code**:
   ```ruby
   # Before
   - greeting = "Hello #{user.name}!"

   # After (two-step)
   + prompt = Langfuse.client.get_prompt("user-greeting")
   + greeting = prompt.compile(name: user.name)

   # Or after (one-step with fallback)
   + greeting = Langfuse.client.compile_prompt("user-greeting",
   +   variables: { name: user.name },
   +   fallback: "Hello {{name}}!",
   +   type: :text
   + )
   ```

5. **Test with Fallbacks**:
   ```ruby
   # Safe rollout with fallback
   prompt = Langfuse.client.get_prompt("user-greeting",
     fallback: "Hello {{name}}!",  # Old hardcoded version
     type: :text
   )
   ```

6. **Monitor and Iterate**:
   - Check Langfuse dashboard for prompt usage
   - A/B test new prompt versions
   - Update prompts without code deployment

### Backward Compatibility

**No breaking changes to existing API**:

```ruby
# Existing tracing still works
client = Langfuse.client
client.trace(name: "my-trace") do |trace|
  trace.generation(name: "llm-call", input: "test")
end

# NEW prompt management is additive (flattened API)
client.get_prompt("greeting")
client.compile_prompt("greeting", variables: { name: "Alice" })
```

### Rollback Plan

If issues arise:

1. **Use Fallbacks**: All prompts have fallback option
2. **Disable Caching**: Set `cache_ttl_seconds: 0`
3. **Revert to Hardcoded**: Fallback to old prompt logic
4. **Pin Old Version**: `gem "langfuse-ruby", "~> 0.1.4"`

---

## Trade-offs and Alternatives

### Design Decision Matrix

| Decision | Chosen Approach | Alternative | Trade-off |
|----------|----------------|-------------|-----------|
| **Templating** | Mustache | ERB | Security vs. convenience |
| **HTTP Client** | Faraday | HTTParty | Flexibility vs. simplicity |
| **Caching** | In-memory | Rails.cache | Speed vs. distribution |
| **Thread Safety** | Mutex | Thread-local | Simplicity vs. performance |
| **API Style** | Keyword args | Positional | Readability vs. brevity |

### 1. Templating: Mustache vs. ERB

**Chosen: Mustache**

- **Pro**: Logic-less, secure, cross-SDK consistency
- **Pro**: No arbitrary code execution risk
- **Con**: No conditionals or loops (must be done in code)

**Alternative: ERB**

- **Pro**: Built-in, no dependency
- **Pro**: Full Ruby power (conditionals, loops)
- **Con**: Security risk (code injection)
- **Con**: Different from JS SDK

**Decision Rationale**: Security and consistency outweigh convenience.

### 2. Caching: In-memory vs. Rails.cache

**Chosen: In-memory (Phase 1), Rails.cache optional (Phase 2)**

**In-memory**:
- **Pro**: Extremely fast (<1ms)
- **Pro**: No external dependencies
- **Con**: Not shared across processes
- **Con**: Higher memory per-process

**Rails.cache (Redis)**:
- **Pro**: Shared across all processes/servers
- **Pro**: Centralized cache management
- **Con**: 10-100x slower than in-memory
- **Con**: Requires Redis dependency

**Decision Rationale**: Start with simplest approach, add distribution as opt-in.

### 3. Thread Safety: Mutex vs. Thread-local

**Chosen: Mutex**

- **Pro**: Simple, proven approach
- **Pro**: Shared cache across threads
- **Con**: Lock contention under high load

**Alternative: Thread-local Storage**

- **Pro**: No locking, faster
- **Con**: Duplicated cache per thread
- **Con**: Higher memory usage

**Decision Rationale**: Rails apps typically have limited threads per process, mutex overhead acceptable.

### 4. Async Refresh: Threads vs. Fibers

**Chosen: Threads (Phase 1), consider Fibers (Phase 2)**

**Threads**:
- **Pro**: Built-in, familiar
- **Con**: Heavier weight

**Fibers**:
- **Pro**: Lightweight concurrency
- **Pro**: Better for high-concurrency scenarios
- **Con**: Requires Ruby 3.0+
- **Con**: Less familiar to developers

**Decision Rationale**: Threads are sufficient for MVP, evaluate Fibers based on real-world performance.

### 5. API Style: Keyword Args vs. Options Hash

**Chosen: Keyword Arguments**

```ruby
# Keyword args (chosen)
prompt.get("name", version: 2, label: "production")

# Options hash (alternative)
prompt.get("name", { version: 2, label: "production" })
```

**Rationale**: Keyword args provide better IDE autocomplete and explicit API.

---

## Open Questions

### 1. Rails.cache Integration Priority

**Question**: Should Rails.cache integration be Phase 1 or Phase 2?

**Options**:
- **A**: Phase 1 - Implement both backends from start
- **B**: Phase 2 - Start simple with in-memory

**Recommendation**: **Phase 2**
- Rationale: In-memory is sufficient for most use cases, easier to test, faster to ship MVP

### 2. Async Background Refresh

**Question**: How to implement background refresh in stale-while-revalidate?

**Options**:
- **A**: Simple threads (`Thread.new { ... }`)
- **B**: Sidekiq jobs (requires Sidekiq dependency)
- **C**: Fibers (requires Ruby 3.0+)

**Recommendation**: **Simple threads**
- Rationale: No additional dependencies, sufficient for prompt refresh use case

### 3. Prompt Validation

**Question**: Should we validate prompt structure before sending to API?

**Options**:
- **A**: Client-side validation (check required fields)
- **B**: Rely on API validation (simpler)

**Recommendation**: **API validation**
- Rationale: Avoid duplicating server logic, API is source of truth

### 4. LangChain Dependency

**Question**: Should we depend on `langchain-ruby` gem for `to_langchain` methods?

**Options**:
- **A**: Hard dependency (import LangChain types)
- **B**: Soft dependency (return plain Ruby hashes)
- **C**: Optional dependency (only load if available)

**Recommendation**: **Soft dependency**
- Rationale: Return plain hashes that work with LangChain without requiring the gem

### 5. Observability Hooks

**Question**: What observability should be built-in?

**Options**:
- **A**: Logging only (simple)
- **B**: StatsD metrics (cache hits, API latency)
- **C**: OpenTelemetry traces (full observability)

**Recommendation**: **Logging + StatsD hooks**
- Rationale: Logging is essential, StatsD is common in Rails, OpenTelemetry can be Phase 3

### 6. Configuration Pattern

**Question**: Global config vs. per-client config?

**Options**:
- **A**: Global: `Langfuse.configure { |c| ... }`
- **B**: Per-client: `Langfuse::Client.new(config)`
- **C**: Both (global defaults, per-client overrides)

**Recommendation**: **Both**
- Rationale: Global config for Rails initializer, per-client for multi-tenant apps

```ruby
# Global config
Langfuse.configure do |config|
  config.public_key = ENV["LANGFUSE_PUBLIC_KEY"]
  config.secret_key = ENV["LANGFUSE_SECRET_KEY"]
  config.cache_backend = :rails
end

# Per-client override
client = Langfuse::Client.new(
  public_key: tenant.langfuse_key,
  cache_backend: :memory
)
```

### 7. Prompt Versioning Strategy

**Question**: How to handle version conflicts between cache and API?

**Scenario**: Prompt version 1 is cached, version 2 is promoted to production

**Options**:
- **A**: Cache by label (current approach - auto-updates)
- **B**: Cache by version (explicit, never changes)
- **C**: Configurable cache key strategy

**Recommendation**: **Cache by label (default), support version caching**
- Rationale: Labels enable dynamic updates, versions for stability

---

## Appendix: ASCII Diagrams

### Caching Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    get("greeting")                           │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
         ┌─────────────────────────┐
         │  Check cache for key    │
         │  "greeting-label:prod"  │
         └─────────┬───────────────┘
                   │
         ┌─────────┴─────────┐
         │                   │
         ▼                   ▼
    ┌────────┐         ┌─────────┐
    │ MISS   │         │  HIT    │
    └────┬───┘         └────┬────┘
         │                  │
         │            ┌─────┴──────┐
         │            │            │
         │            ▼            ▼
         │       ┌────────┐  ┌──────────┐
         │       │ FRESH  │  │ EXPIRED  │
         │       └───┬────┘  └────┬─────┘
         │           │            │
         │           ▼            ▼
         │     ┌──────────┐  ┌────────────────┐
         │     │ Return   │  │ Return stale + │
         │     │ cached   │  │ refresh async  │
         │     └──────────┘  └────────────────┘
         │
         ▼
    ┌────────────────┐
    │ Fetch from API │
    └────────┬───────┘
             │
       ┌─────┴──────┐
       │            │
       ▼            ▼
  ┌─────────┐  ┌──────────┐
  │ SUCCESS │  │  ERROR   │
  └────┬────┘  └────┬─────┘
       │            │
       │      ┌─────┴──────┐
       │      │            │
       │      ▼            ▼
       │  ┌─────────┐  ┌─────────┐
       │  │Fallback?│  │  Raise  │
       │  └────┬────┘  └─────────┘
       │       │
       │       ▼
       │  ┌──────────────┐
       │  │Return fallback│
       │  └──────────────┘
       │
       ▼
  ┌──────────────┐
  │ Store cache  │
  └──────┬───────┘
         │
         ▼
  ┌──────────────┐
  │Return prompt │
  └──────────────┘
```

### Class Hierarchy

```
Langfuse::Client
│
├── prompt: PromptManager
│   │
│   ├── cache: PromptCache
│   │   ├── CacheItem (value, expiry)
│   │   └── Methods: get, set, invalidate
│   │
│   ├── api_client: ApiClient
│   │   └── Methods: get_prompt, create_prompt, update_prompt
│   │
│   └── Methods: get, create, update
│
└── (existing methods: trace, generation, etc.)


Prompt Client Hierarchy:

BasePromptClient (abstract)
│
├── TextPromptClient
│   ├── compile(variables)
│   └── to_langchain()
│
└── ChatPromptClient
    ├── compile(variables, placeholders)
    └── to_langchain(placeholders:)
```

### Request Flow

```
Application Code
      │
      │ client.prompt.get("greeting")
      ▼
PromptManager
      │
      │ 1. Check cache
      ▼
PromptCache
      │
      ├──[MISS]──────────┐
      │                  │
      │                  ▼
      │            ApiClient
      │                  │
      │                  │ 2. GET /api/v2/prompts/greeting
      │                  ▼
      │            Langfuse API
      │                  │
      │                  │ 3. Response: { name, version, prompt, ... }
      │                  ▼
      │            ApiClient
      │                  │
      │                  │ 4. Parse response
      │                  ▼
      │            PromptManager
      │                  │
      │                  │ 5. Build client (Text/Chat)
      │                  ▼
      │            TextPromptClient / ChatPromptClient
      │                  │
      │                  │ 6. Store in cache
      │                  ▼
      │            PromptCache
      │
      │ [HIT: FRESH]
      ├──────────────────┐
      │                  │
      │                  │ 7. Return from cache
      │                  ▼
      │            TextPromptClient / ChatPromptClient
      │
      │ [HIT: EXPIRED]
      └──────────────────┐
                         │
                         │ 8a. Return stale
                         ▼
                   TextPromptClient / ChatPromptClient
                         │
                         │ 8b. Background refresh
                         ▼
                   (Async: steps 2-6)
```

---

## Design Revisions and Improvements

This section documents critical fixes and improvements made to the design based on technical review.

### Critical Fixes Applied

1. **Non-blocking Background Refresh** (Lines 389-400)
   - **Issue**: `promise.join` blocked calling thread, defeating stale-while-revalidate
   - **Fix**: Cleanup happens in separate thread to maintain non-blocking behavior
   - **Impact**: Ensures fast response times even with expired cache

2. **Connection Singleton Bug** (Lines 816-831)
   - **Issue**: Mutable timeout on shared connection affected all subsequent requests
   - **Fix**: Create dedicated connection instances for custom timeouts
   - **Impact**: Prevents timeout configuration from leaking between requests

3. **Removed Double Retry Logic** (Lines 771-783)
   - **Issue**: Manual retries + Faraday middleware = up to 4 retries instead of 2
   - **Fix**: Rely solely on Faraday retry middleware
   - **Impact**: Predictable retry behavior, cleaner code

4. **Cache Stampede Protection** (Lines 379-387)
   - **Issue**: 1000 concurrent requests on expired cache = 1000 API calls
   - **Fix**: Track refreshing keys, only first requester triggers refresh
   - **Impact**: Prevents API rate limit exhaustion

5. **Bounded Thread Pool** (Lines 514-557)
   - **Issue**: Unbounded thread creation during cache refreshes
   - **Fix**: Use `concurrent-ruby` FixedThreadPool (max 5 threads)
   - **Impact**: Prevents thread exhaustion, controls concurrent API calls

### Important Enhancements

6. **LRU Cache Eviction** (Lines 362-378, 417-434)
   - **Addition**: Max cache size (1000 entries) with LRU eviction policy
   - **Benefit**: Prevents unbounded memory growth
   - **Implementation**: Track access order, evict least recently used

7. **Fallback Type Validation** (Lines 281-298)
   - **Addition**: Validate fallback matches specified type (text/chat)
   - **Benefit**: Prevent runtime errors from type mismatches
   - **Example**: Reject text fallback when type is :chat

8. **Cache Invalidation Safety** (Lines 268-276)
   - **Issue**: Cache invalidated even on failed API updates
   - **Fix**: Only invalidate after successful API response
   - **Impact**: Prevents serving stale data after failed updates

9. **Placeholder Validation** (Lines 588-630)
   - **Addition**: Validate placeholder structure, handle empty arrays
   - **Addition**: Support required_placeholders parameter
   - **Benefit**: Better error messages, fail fast on invalid data

10. **Security Documentation** (Lines 1527-1545)
    - **Addition**: Document sanitization rationale (DoS prevention)
    - **Addition**: Configurable max_length parameter
    - **Benefit**: Clear security posture, flexible limits

### Testing Enhancements

11. **Edge Case Coverage** (Lines 2010-2074)
    - Added: Cache stampede protection tests
    - Added: Cache expiry edge case tests
    - Added: LRU eviction tests
    - Added: Concurrent access tests
    - **Impact**: >95% confidence in production behavior

### Observability Additions

12. **Built-in Instrumentation** (Lines 318-357)
    - **Addition**: ActiveSupport::Notifications integration
    - **Metrics**: cache hits, duration, fallback usage
    - **Integration**: Easy StatsD/Datadog hookup
    - **Impact**: Production visibility without custom code

### Timeline Adjustments

13. **Realistic Estimates** (Lines 1619, 1648, 1698, 1704)
    - Phase 1: 2-3 days → **3-4 days** (edge cases + thorough testing)
    - Phase 2: 2 days → **2-3 days**
    - Phase 4: 1-2 days → **2-3 days** (comprehensive observability)
    - Total: 6-8 days → **8-11 days** (30% contingency buffer)
    - **Rationale**: Account for code review, testing, documentation

### Dependency Updates

14. **New Required Dependency** (Line 2235)
    - **Added**: `concurrent-ruby ~> 1.2`
    - **Purpose**: Thread pool for bounded concurrency
    - **Justification**: Production-grade thread primitives, prevents resource exhaustion

---

## API Evolution: Original vs LaunchDarkly-Inspired Design

This section documents the evolution from the initial nested API design to the final LaunchDarkly-inspired flattened API.

### Design Comparison

| Aspect | Original Design | LaunchDarkly-Inspired (Final) |
|--------|----------------|-------------------------------|
| **API Structure** | Nested: `client.prompt.get()` | Flat: `client.get_prompt()` |
| **Configuration** | Inline only | Global config + per-client |
| **Global Client** | No | `Langfuse.client` singleton |
| **Fallback Pattern** | Optional, raises on error | Encouraged, returns fallback |
| **Convenience Methods** | No | `compile_prompt()` for one-step |
| **Detail Variants** | No | `get_prompt_detail()` for debugging |
| **Method Count** | 3 (get, create, update) | 6 (get_prompt, get_prompt_detail, compile_prompt, create_prompt, update_prompt, invalidate_cache) |
| **State Checking** | No | `initialized?` |

### Code Comparison

#### Initialization

```ruby
# Original
client = Langfuse::Client.new(
  public_key: ENV['LANGFUSE_PUBLIC_KEY'],
  secret_key: ENV['LANGFUSE_SECRET_KEY']
)

# LaunchDarkly-Inspired
Langfuse.configure do |config|
  config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
  config.secret_key = ENV['LANGFUSE_SECRET_KEY']
  config.cache_ttl = 120
end
client = Langfuse.client
```

#### Get Prompt

```ruby
# Original (nested)
prompt = client.prompt.get("greeting")
compiled = prompt.compile(name: "Alice")

# LaunchDarkly-Inspired (flattened, two options)
# Option 1: Two-step (same as original)
prompt = client.get_prompt("greeting")
compiled = prompt.compile(name: "Alice")

# Option 2: One-step convenience
compiled = client.compile_prompt("greeting", variables: { name: "Alice" })
```

#### With Fallback

```ruby
# Original
begin
  prompt = client.prompt.get("greeting")
rescue Langfuse::NotFoundError
  prompt = client.prompt.get("greeting", fallback: "Hello!", type: :text)
end

# LaunchDarkly-Inspired (graceful by default)
prompt = client.get_prompt("greeting",
  fallback: "Hello {{name}}!",
  type: :text
)
# Never raises - returns fallback on error
```

#### Debugging

```ruby
# Original (no built-in support)
start = Time.now
prompt = client.prompt.get("greeting")
duration = Time.now - start
Rails.logger.info("Fetched in #{duration}s")

# LaunchDarkly-Inspired (built-in)
detail = client.get_prompt_detail("greeting")
# => {
#   prompt: ...,
#   cached: true,
#   version: 3,
#   fetch_time_ms: 1.2,
#   source: :cache
# }
```

### Why the Change?

The LaunchDarkly-inspired design provides:

1. **Simpler Mental Model**: Everything on `Client`, no nested managers
2. **Better Rails Integration**: Global config and singleton pattern
3. **More Resilient**: Fallbacks encouraged, graceful degradation
4. **Better DX**: Convenience methods reduce boilerplate
5. **Better Observability**: Detail variants for debugging
6. **Industry Pattern**: Familiar to developers using LaunchDarkly

The additional methods and slight API surface increase are worth the improved developer experience and production reliability.

---

## Summary and Next Steps

### Summary

This design document outlines a comprehensive plan to add prompt management functionality to the `langfuse-ruby` gem, achieving feature parity with the JavaScript SDK while incorporating LaunchDarkly's exceptional API design patterns.

**Key Highlights**:

1. **LaunchDarkly-Inspired API**: Flattened API surface, global configuration, singleton pattern
2. **Architecture**: Clean separation of concerns (Config, Client, Cache, Clients, API)
3. **Performance**: Sub-ms cache hits with stale-while-revalidate
4. **Thread Safety**: Mutex-based synchronization for Rails apps
5. **Developer Experience**: Intuitive API, convenience methods, fallback support, observability
6. **Incremental Rollout**: 4 phases from MVP to production-ready

### Next Steps

1. **Review and Feedback**:
   - [ ] Architecture review with team
   - [ ] API design feedback from early users
   - [ ] Security review (authentication, input validation)

2. **Phase 1 Implementation** (Week 1-2):
   - [ ] Set up project structure
   - [ ] Implement core classes (Manager, Cache, Clients)
   - [ ] Add ApiClient extensions
   - [ ] Write comprehensive tests
   - [ ] Documentation and examples

3. **Beta Release**:
   - [ ] Publish `0.2.0.beta1` to RubyGems
   - [ ] Gather feedback from early adopters
   - [ ] Iterate based on real-world usage

4. **Phase 2-4** (Week 3-4):
   - [ ] Advanced features (create, update, placeholders)
   - [ ] Rails.cache integration
   - [ ] LangChain helpers
   - [ ] Performance optimization

5. **Production Release**:
   - [ ] Final QA and testing
   - [ ] Complete documentation
   - [ ] Migration guides
   - [ ] Publish `0.2.0` stable

### Success Criteria

**Technical**:
- [ ] All JavaScript SDK features implemented
- [ ] >90% test coverage
- [ ] Thread-safe for production Rails apps
- [ ] <100ms p95 latency for cached prompts

**Documentation**:
- [ ] Complete API reference
- [ ] Migration guide from hardcoded prompts
- [ ] Integration examples (Rails, LangChain)
- [ ] Troubleshooting guide

**Adoption**:
- [ ] 10+ beta users providing feedback
- [ ] Zero critical bugs in production
- [ ] Positive developer feedback

---

**Document End**
