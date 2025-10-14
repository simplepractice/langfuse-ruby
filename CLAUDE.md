# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is the official **Langfuse Ruby SDK**, providing LLM tracing, observability, and prompt management capabilities. The project is being built from scratch following an iterative, test-driven approach inspired by LaunchDarkly's API design patterns.

**Key Design Principles:**
- **LaunchDarkly-Inspired API**: Flat API surface with all methods on `Client` (not nested managers)
- **Rails-Friendly**: Global configuration pattern with `Langfuse.configure` block
- **Iterative Development**: Build small, testable increments following the implementation plan
- **Minimal Dependencies**: Only add dependencies when needed
- **Thread-Safe**: Safe for multi-threaded environments

## Requirements

- **Ruby**: >= 3.2.0 (specified in `.ruby-version` and `langfuse.gemspec`)
- No Rails dependency - works in any Ruby project

## Common Commands

### Running Tests
```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/langfuse_spec.rb

# Run specific test at line number
bundle exec rspec spec/langfuse_spec.rb:10

# Run tests with coverage report
bundle exec rspec
# Coverage report opens automatically in browser (see coverage/index.html)
```

### Code Quality
```bash
# Run linter with auto-fix
bundle exec rubocop -a

# Run linter without auto-fix
bundle exec rubocop

# Check specific file
bundle exec rubocop lib/langfuse.rb
```

### Development Setup
```bash
# Install dependencies
bundle install

# Check test status
bundle exec rspec
```

## Architecture

### Current Structure (Phase 0 Complete)
```
lib/
├── langfuse.rb                 # Main entry point with global config
└── langfuse/
    └── version.rb              # Gem version

spec/
├── spec_helper.rb              # RSpec config with SimpleCov
└── langfuse_spec.rb            # Basic tests
```

### Planned Structure (As Implementation Progresses)
```
lib/langfuse/
├── config.rb                   # Configuration object (Phase 1.1)
├── api_client.rb               # HTTP layer with Faraday (Phase 1.2)
├── errors.rb                   # Error classes (Phase 1.3)
├── client.rb                   # Main client with flat API (Phase 2.3)
├── text_prompt_client.rb       # Text prompt wrapper (Phase 2.1)
├── chat_prompt_client.rb       # Chat prompt wrapper (Phase 2.2)
└── prompt_cache.rb             # Caching logic (Phase 4.1)
```

### API Design Pattern (Critical!)

**✅ CORRECT - Flat API (LaunchDarkly style):**
```ruby
client.get_prompt("name")
client.compile_prompt("name", variables: {})
client.create_prompt(...)
```

**❌ INCORRECT - Nested managers:**
```ruby
client.prompt.get("name")          # Don't do this
client.prompt_manager.compile(...) # Don't do this
```

### Global Configuration Pattern
```ruby
# Rails initializer or configuration file
Langfuse.configure do |config|
  config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
  config.secret_key = ENV['LANGFUSE_SECRET_KEY']
  config.cache_ttl = 60
end

# Use global singleton client
client = Langfuse.client
prompt = client.get_prompt("greeting")
```

### Ruby Conventions

- **snake_case** for all methods: `get_prompt`, not `getPrompt`
- **Symbol keys** in hashes: `{ role: :user }`, not `{ "role" => "user" }`
- **Keyword arguments**: `get_prompt(name, version: 2)`, not `get_prompt(name, { version: 2 })`
- **Blocks for config**: `configure { |c| ... }`
- **Double quotes** for strings (per Rubocop config)

## Development Workflow

### Implementation Process

This project follows a **strict phase-based approach**. See `IMPLEMENTATION_PLAN.md` for the detailed roadmap.

**Current Status**: Phase 0 (Foundation) is complete, ready for Phase 1 (HTTP Client)

**Before writing code:**
1. Check `PROGRESS.md` to see current phase
2. Read the relevant section in `IMPLEMENTATION_PLAN.md`
3. Follow the checklist for that increment
4. Update `PROGRESS.md` when phase is complete

**Important Guidelines:**
- Build incrementally - don't jump ahead to future phases
- Write tests FIRST for each new component
- Keep test coverage >90% (target for Phase 6, currently 50% minimum)
- Each phase should leave the gem in a working state

### Quick Reference Files

- **`IMPLEMENTATION_PLAN.md`**: Detailed phase-by-phase implementation plan with checklists
- **`QUICK_REFERENCE.md`**: Design decisions, patterns, and conventions
- **`PROGRESS.md`**: Current status and completed milestones
- **`langfuse-ruby-prompt-management-design.md`**: Complete design specification

### Testing Strategy

**Test Coverage Target**: >90% by Phase 6 (currently 50% minimum)

**Test Types:**
- Unit tests for each class in isolation
- Integration tests for `Client → ApiClient → (mocked HTTP)`
- WebMock for HTTP stubbing
- VCR tests for real API responses (Phase 2+)

**Common Test Pattern:**
```ruby
RSpec.describe Langfuse::SomeClass do
  describe "#some_method" do
    context "when condition is met" do
      it "does the expected thing" do
        # Arrange, Act, Assert
      end
    end
  end
end
```

**Important Testing Notes:**
- WebMock disables external HTTP by default (see `spec_helper.rb`)
- SimpleCov generates coverage report automatically
- Global `Langfuse.reset!` runs before each test
- Use `instance_double` for mocking dependencies

## Code Style

### Rubocop Configuration

The project uses Rubocop with the following key settings:
- **Target Ruby Version**: 3.2
- **Line Length**: 120 characters max
- **String Literals**: Double quotes enforced
- **Documentation**: Disabled (use YARD format when adding docs in Phase 10)

### Method Length
- Max 20 lines (excluding specs)
- Break longer methods into smaller, testable units

### Naming Conventions
- **Classes**: `PascalCase` (e.g., `TextPromptClient`)
- **Methods**: `snake_case` (e.g., `get_prompt`)
- **Constants**: `SCREAMING_SNAKE_CASE` (e.g., `DEFAULT_TTL`)
- **Instance vars**: `@snake_case` (e.g., `@api_client`)

## Dependencies

### Current Dependencies (Phase 0)
**Runtime**: None yet
**Development**: `rspec`, `rubocop`, `rubocop-rspec`, `simplecov`, `webmock`, `rake`

### Planned Dependencies by Phase

**Phase 1 (HTTP Client)**:
- `faraday ~> 2.0` - HTTP client
- `faraday-retry ~> 2.0` - Retry logic

**Phase 3 (Variable Substitution)**:
- `mustache ~> 1.1` - Template compilation

**Phase 7 (Advanced Caching)**:
- `concurrent-ruby ~> 1.2` - Thread pool for background refreshes

**Phase 8 (CRUD)**:
- `vcr ~> 6.1` (dev) - HTTP recording

## Key Concepts

### Prompt Types

**Text Prompts**: Simple string templates with Mustache variables
```ruby
# Template: "Hello {{name}}!"
prompt.compile(name: "Alice") # => "Hello Alice!"
```

**Chat Prompts**: Array of message hashes with roles
```ruby
# Template: [{ role: "system", content: "You are {{role}}" }]
prompt.compile({ role: "helper" }) # => [{ role: "system", content: "You are helper" }]
```

### Variable Substitution

Uses **Mustache templating** (logic-less, no conditionals/loops):
- Syntax: `{{variable_name}}`
- Secure (no code execution)
- Same syntax as Langfuse JavaScript SDK

### Caching Strategy

**Phase 4 (Simple)**: In-memory cache with TTL
**Phase 7 (Advanced)**: LRU eviction, stale-while-revalidate, stampede protection

## Important References

- **Design Document**: `langfuse-ruby-prompt-management-design.md` - Complete API specification
- **Implementation Plan**: `IMPLEMENTATION_PLAN.md` - Phase-by-phase development plan
- **Quick Reference**: `QUICK_REFERENCE.md` - Patterns and conventions
- **LaunchDarkly Ruby SDK**: https://github.com/launchdarkly/ruby-server-sdk (API inspiration)
- **Langfuse API Docs**: https://langfuse.com/docs/api
- **Langfuse TypeScript SDK**: https://github.com/langfuse/langfuse-js (reference implementation)

## Phase Milestones

After each phase, the gem should be able to:

- **Phase 0**: Run `bundle exec rspec` successfully ✅
- **Phase 1**: Fetch a real prompt from Langfuse API
- **Phase 2**: Return prompt objects with metadata
- **Phase 3**: Compile prompts with variable substitution
- **Phase 4**: Cache prompts with TTL
- **Phase 5**: Use `Langfuse.configure` and `Langfuse.client` globally
- **Phase 6**: Handle API errors gracefully with fallback support
- **Phase 7**: Production-grade caching with background refresh
- **Phase 8**: Create and update prompts via API
- **Phase 9**: Convert prompts to LangChain format
- **Phase 10**: 1.0 Release ready with full documentation
