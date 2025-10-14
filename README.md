# Langfuse Ruby SDK

Official Ruby SDK for [Langfuse](https://langfuse.com) - Open-source LLM observability and prompt management.

[![Gem Version](https://badge.fury.io/rb/langfuse.svg)](https://badge.fury.io/rb/langfuse)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.2.0-ruby.svg)](https://www.ruby-lang.org/en/)

## 🚧 Under Active Development

This gem is currently being built from scratch following an iterative, test-driven approach. Check the [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) to see what's completed and what's coming next.

## Vision

The Langfuse Ruby SDK will provide:

- **Prompt Management**: Fetch, cache, and compile prompts with variable substitution
- **LLM Tracing**: Track LLM calls, generations, and traces (coming soon)
- **Observability**: Monitor performance and costs (coming soon)
- **LaunchDarkly-Inspired API**: Clean, intuitive Ruby interface

## Quick Start (Coming Soon)

```ruby
# Install
gem install langfuse

# Configure
Langfuse.configure do |config|
  config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
  config.secret_key = ENV['LANGFUSE_SECRET_KEY']
end

# Use
client = Langfuse.client
prompt = client.get_prompt("greeting")
text = prompt.compile(name: "Alice")
```

## Requirements

- Ruby >= 3.2.0

## Development Status

See [PROGRESS.md](PROGRESS.md) for current status and [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for the detailed roadmap.

## Development Setup

```bash
# Clone the repository
git clone https://github.com/langfuse/langfuse-ruby.git
cd langfuse-ruby

# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run linter
bundle exec rubocop
```

## Architecture

The gem follows a clean, modular architecture inspired by LaunchDarkly:

- **Flat API**: All methods on `Client`, no nested managers
- **Global Config**: Rails-friendly configuration pattern
- **Thread-Safe**: Safe for multi-threaded environments
- **Minimal Dependencies**: Only add what's needed

## Contributing

We welcome contributions! This project is being built iteratively, so check the [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) to see what's currently being worked on.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Links

- [Langfuse Documentation](https://langfuse.com/docs)
- [API Reference](https://api.reference.langfuse.com)
- [Design Document](langfuse-ruby-prompt-management-design.md)

## Support

- [GitHub Issues](https://github.com/langfuse/langfuse-ruby/issues)
- [Langfuse Discord](https://langfuse.com/discord)
