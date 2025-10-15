# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project setup
- Basic gem structure
- RSpec test framework
- Rubocop linter configuration

## [0.1.0] - 2025-10-13

### Added
- Complete prompt management system for text and chat prompts
- HTTP client with authentication, retry logic, and exponential backoff
- In-memory caching with TTL and LRU eviction
- Mustache-based variable substitution for prompt templating
- Global configuration pattern with `Langfuse.configure` block
- Fallback prompt support for graceful error recovery
- Thread-safe cache implementation using Monitor
- Comprehensive error handling (`NotFoundError`, `UnauthorizedError`, `ApiError`)
- Support for prompt versioning and label-based fetching
- Environment variable configuration support
- 99.6% test coverage with 221 comprehensive test cases

[Unreleased]: https://github.com/langfuse/langfuse-ruby/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/langfuse/langfuse-ruby/releases/tag/v0.1.0
