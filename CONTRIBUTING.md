# Contributing to Langfuse Ruby SDK

Thank you for your interest in contributing to the Langfuse Ruby SDK! This document provides guidelines for development, testing, and submitting contributions.

## Table of Contents

- [Development Setup](#development-setup)
- [Running Tests](#running-tests)
- [Code Quality](#code-quality)
- [Submitting Issues](#submitting-issues)
- [Submitting Pull Requests](#submitting-pull-requests)
- [Code Style Guidelines](#code-style-guidelines)

## Development Setup

### Requirements

- Ruby >= 3.2.0 (specified in `.ruby-version`)
- Bundler >= 2.0

### Initial Setup

1. Fork and clone the repository:
   ```bash
   git clone https://github.com/YOUR-USERNAME/langfuse-ruby.git
   cd langfuse-ruby
   ```

2. Install dependencies:
   ```bash
   bundle install
   ```

3. Verify the setup by running tests:
   ```bash
   bundle exec rspec
   ```

## Running Tests

### Run All Tests

```bash
bundle exec rspec
```

### Run Specific Test File

```bash
bundle exec rspec spec/langfuse/client_spec.rb
```

### Run Specific Test at Line Number

```bash
bundle exec rspec spec/langfuse/client_spec.rb:42
```

### Test Coverage

The project uses SimpleCov for test coverage reporting:

- Coverage reports are automatically generated when running tests
- View the report at `coverage/index.html`
- Target coverage: >95%
- Current coverage: 99.7%

## Code Quality

### Linter (Rubocop)

Run Rubocop with auto-fix:

```bash
bundle exec rubocop -a
```

Run Rubocop without auto-fix (check only):

```bash
bundle exec rubocop
```

Check specific file:

```bash
bundle exec rubocop lib/langfuse/client.rb
```

### Code Style

The project follows Ruby community conventions:

- **Ruby Version**: Target Ruby 3.2+
- **Line Length**: Max 120 characters
- **String Literals**: Double quotes enforced
- **Naming**:
  - Classes: `PascalCase`
  - Methods: `snake_case`
  - Constants: `SCREAMING_SNAKE_CASE`
- **Method Length**: Max 20 lines (excluding specs)

## Submitting Issues

### Bug Reports

When submitting a bug report, please include:

1. **Clear Title**: Brief description of the issue
2. **Ruby Version**: Output of `ruby --version`
3. **Gem Version**: Version of langfuse gem you're using
4. **Steps to Reproduce**: Minimal code example that reproduces the issue
5. **Expected Behavior**: What you expected to happen
6. **Actual Behavior**: What actually happened
7. **Error Messages**: Full error messages and stack traces

#### Example Bug Report

```markdown
### Bug: get_prompt fails with 401 error despite valid credentials

**Ruby Version:** ruby 3.2.2 (2023-03-30 revision e51014f9c0)
**Gem Version:** langfuse 1.0.0

**Steps to Reproduce:**
\`\`\`ruby
Langfuse.configure do |config|
  config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
  config.secret_key = ENV['LANGFUSE_SECRET_KEY']
end

prompt = Langfuse.client.get_prompt("greeting")
\`\`\`

**Expected:** Fetch prompt successfully
**Actual:** Raises `Langfuse::UnauthorizedError: 401 Unauthorized`

**Error Message:**
\`\`\`
Langfuse::UnauthorizedError: Invalid credentials
  from lib/langfuse/api_client.rb:45:in `get_prompt'
\`\`\`
```

### Feature Requests

When requesting a feature:

1. **Use Case**: Describe your use case and why this feature is needed
2. **Proposed Solution**: If applicable, describe how you envision the feature working
3. **Alternatives**: Any alternative solutions you've considered
4. **Additional Context**: Any other relevant information

### Reproduction Test (Highly Recommended)

If possible, include a failing test that demonstrates the issue:

```ruby
# spec/langfuse/bug_reproduction_spec.rb
require 'spec_helper'

RSpec.describe "Bug: prompt caching not working" do
  it "caches prompts between requests" do
    client = Langfuse::Client.new(config)

    # First request
    prompt1 = client.get_prompt("greeting")

    # Second request (should use cache)
    prompt2 = client.get_prompt("greeting")

    # This fails - both requests hit the API
    expect(api_calls_count).to eq(1)  # Currently fails with 2
  end
end
```

This makes it much easier for maintainers to understand and fix the issue!

## Submitting Pull Requests

### Before Submitting

1. **Run all tests**: Ensure `bundle exec rspec` passes
2. **Run linter**: Ensure `bundle exec rubocop -a` has no offenses
3. **Add tests**: Include tests for any new functionality or bug fixes
4. **Update documentation**: Update README.md if adding user-facing features
5. **Check coverage**: Maintain or improve test coverage

### Pull Request Process

1. **Fork the Repository**: Create your own fork
2. **Create a Feature Branch**:
   ```bash
   git checkout -b feature/my-new-feature
   ```
3. **Make Your Changes**: Write code, tests, and documentation
4. **Commit Your Changes**:
   ```bash
   git commit -m "Add feature: description of feature"
   ```
5. **Push to Your Fork**:
   ```bash
   git push origin feature/my-new-feature
   ```
6. **Open a Pull Request**: Submit PR against the `main` branch

### Pull Request Guidelines

- **Title**: Clear, concise description of the change
- **Description**:
  - What changed and why
  - Link to any related issues
  - Screenshots/examples if applicable
- **Tests**: All tests must pass
- **Coverage**: Maintain >95% coverage
- **Documentation**: Update docs if needed
- **Commits**: Keep commits focused and atomic

### Example Pull Request Description

```markdown
## Summary
Adds support for custom timeout configuration per API call.

## Motivation
Users need fine-grained control over request timeouts for different operations.

## Changes
- Added `timeout` option to `get_prompt` method
- Updated `ApiClient` to support per-request timeouts
- Added tests for timeout configuration
- Updated README with timeout examples

## Testing
- Added 5 new test cases covering timeout scenarios
- All existing tests pass
- Coverage increased from 99.6% to 99.7%

Closes #123
```

## Code Style Guidelines

### Writing Tests

Follow the Arrange-Act-Assert pattern:

```ruby
RSpec.describe Langfuse::Client do
  describe "#get_prompt" do
    context "when prompt exists" do
      it "returns the prompt" do
        # Arrange
        stub_api_request
        client = Langfuse::Client.new(config)

        # Act
        prompt = client.get_prompt("greeting")

        # Assert
        expect(prompt.name).to eq("greeting")
      end
    end
  end
end
```

### Error Handling

Provide clear, actionable error messages:

```ruby
# ✅ Good
raise ArgumentError, "fallback must be a String for text prompts, got #{fallback.class}. " \
                     "For chat prompts, use an Array of message hashes."

# ❌ Bad
raise ArgumentError, "Invalid fallback type"
```

### Documentation

Use YARD format for public APIs:

```ruby
# Get a prompt from Langfuse with caching support
#
# @param name [String] The prompt name
# @param options [Hash] Options hash
# @option options [Integer] :version Specific version number
# @option options [String] :label Label filter (e.g., "production")
# @return [TextPromptClient, ChatPromptClient] The prompt client
# @raise [NotFoundError] If prompt doesn't exist
# @raise [ApiError] If API request fails
#
# @example Fetch latest production prompt
#   prompt = client.get_prompt("greeting", label: "production")
def get_prompt(name, **options)
  # ...
end
```

## Development Tips

### Working with WebMock

Tests use WebMock to stub HTTP requests:

```ruby
require 'webmock/rspec'

stub_request(:get, "https://cloud.langfuse.com/api/public/v2/prompts/greeting")
  .to_return(status: 200, body: response_json, headers: { 'Content-Type' => 'application/json' })
```

### Debugging Tests

Use `binding.pry` (requires `pry` gem):

```ruby
it "debugs the test" do
  require 'pry'
  binding.pry  # Debugger will stop here
  expect(prompt).to eq("Hello")
end
```

### Testing Cache Behavior

```ruby
it "caches prompts" do
  client = Langfuse::Client.new(config)

  # First call hits API
  expect(api_client).to receive(:get_prompt).once.and_call_original
  prompt1 = client.get_prompt("greeting")

  # Second call uses cache (no API call)
  prompt2 = client.get_prompt("greeting")

  expect(prompt1.name).to eq(prompt2.name)
end
```

## Questions or Need Help?

- **Questions**: Open a [GitHub Discussion](https://github.com/langfuse/langfuse-ruby/discussions)
- **Bugs**: Open an [issue](https://github.com/langfuse/langfuse-ruby/issues)
- **Security Issues**: Email security@langfuse.com (do not open public issues)

## License

By contributing to this project, you agree that your contributions will be licensed under the MIT License.

Thank you for contributing to the Langfuse Ruby SDK! 🎉
