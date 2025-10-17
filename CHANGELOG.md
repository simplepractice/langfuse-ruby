# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2025-10-16 🚀

### Initial Release

Complete Ruby SDK for Langfuse with prompt management, distributed caching, LLM tracing, and Rails integration.

#### Prompt Management
- Fetch and compile text and chat prompts with Mustache templating
- Support for prompt versioning and label-based fetching (production, staging, etc.)
- Automatic variable substitution with nested objects and arrays
- Global configuration pattern with `Langfuse.configure` block
- Fallback prompt support for graceful error recovery

#### Caching
- Dual backend support: in-memory (default) and Rails.cache (distributed)
- Thread-safe in-memory cache with TTL and LRU eviction
- Distributed caching with Redis/Memcached via Rails.cache
- Automatic stampede protection with distributed locks (Rails.cache only)
- Cache warming utilities for deployment automation
- Auto-discovery of all prompts with configurable labels

#### LLM Tracing & Observability
- Built on OpenTelemetry for industry-standard distributed tracing
- Block-based Ruby API for traces, spans, and generations
- Automatic prompt-to-trace linking
- Token usage and cost tracking
- W3C Trace Context support for distributed tracing across services
- Integration with APM tools (Datadog, New Relic, Honeycomb, etc.)
- Async processing with batch span export

#### Rails Integration
- Rails-friendly configuration with initializer support
- Background job integration (Sidekiq, GoodJob, Delayed Job, etc.)
- Rake tasks for cache management
- Environment-specific configuration patterns
- Credentials support for secure key management

#### Developer Experience
- Comprehensive error handling with specific error classes
- HTTP client with automatic retry logic and exponential backoff
- Circuit breaker pattern for resilience (via Stoplight)
- 99.7% test coverage with 339 comprehensive test cases
- Extensive documentation with guides for Rails, tracing, and migration

#### Dependencies
- Ruby >= 3.2.0
- No Rails dependency (works with any Ruby project)
- Minimal runtime dependencies (Faraday, Mustache, OpenTelemetry)

[Unreleased]: https://github.com/langfuse/langfuse-ruby/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/langfuse/langfuse-ruby/releases/tag/v1.0.0
