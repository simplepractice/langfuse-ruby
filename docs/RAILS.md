# Rails Integration Guide

Complete guide for integrating the Langfuse Ruby SDK into your Rails application.

## Table of Contents

- [Installation](#installation)
- [Configuration](#configuration)
- [Usage Patterns](#usage-patterns)
- [Background Jobs](#background-jobs)
- [Testing](#testing)
- [Deployment](#deployment)
- [Best Practices](#best-practices)

## Installation

Add to your `Gemfile`:

```ruby
gem 'langfuse'
```

Then run:

```bash
bundle install
```

## Configuration

### Create an Initializer

Create `config/initializers/langfuse.rb`:

```ruby
# config/initializers/langfuse.rb
Langfuse.configure do |config|
  # Required: Authentication
  config.public_key = ENV['LANGFUSE_PUBLIC_KEY']
  config.secret_key = ENV['LANGFUSE_SECRET_KEY']

  # Optional: API Settings
  config.base_url = ENV.fetch('LANGFUSE_BASE_URL', 'https://cloud.langfuse.com')
  config.timeout = 5  # seconds

  # Optional: Caching (recommended for production)
  config.cache_ttl = Rails.env.production? ? 300 : 60  # 5 min in prod, 1 min in dev
  config.cache_max_size = 1000

  # Optional: Logging
  config.logger = Rails.logger

  # Optional: Enable tracing
  config.tracing_enabled = ENV.fetch('LANGFUSE_TRACING_ENABLED', 'false') == 'true'
end
```

### Environment Variables

Add to your `.env` (development) or environment configuration:

```bash
# .env
LANGFUSE_PUBLIC_KEY=pk_...
LANGFUSE_SECRET_KEY=sk_...
LANGFUSE_BASE_URL=https://cloud.langfuse.com
LANGFUSE_TRACING_ENABLED=true
```

### Credentials

For production, use Rails credentials:

```bash
# Edit credentials
rails credentials:edit
```

Add:

```yaml
langfuse:
  public_key: pk_...
  secret_key: sk_...
```

Then in your initializer:

```ruby
Langfuse.configure do |config|
  config.public_key = Rails.application.credentials.dig(:langfuse, :public_key)
  config.secret_key = Rails.application.credentials.dig(:langfuse, :secret_key)
  # ... other config
end
```

## Usage Patterns

### In Controllers

```ruby
class UsersController < ApplicationController
  def create
    # Fetch and compile prompt
    prompt = Langfuse.client.get_prompt("welcome-email", label: "production")
    email_body = prompt.compile(
      user_name: params[:name],
      app_url: root_url
    )

    # Send email
    UserMailer.welcome_email(params[:email], email_body).deliver_later

    render json: { message: "User created" }, status: :created
  end
end
```

### In Service Objects

```ruby
# app/services/ai_assistant_service.rb
class AiAssistantService
  def initialize(user)
    @user = user
    @client = Langfuse.client
  end

  def generate_response(question)
    Langfuse.trace(
      name: "ai-assistant",
      user_id: @user.id.to_s,
      input: { question: question }
    ) do |trace|
      # Get prompt from Langfuse
      prompt = @client.get_prompt("assistant-chat", label: Rails.env)

      # Compile with user context
      messages = prompt.compile(
        user_name: @user.name,
        user_context: @user.context_summary
      )

      # Call LLM with tracing
      response = trace.generation(
        name: "gpt4-response",
        model: "gpt-4",
        prompt: prompt,
        model_parameters: { temperature: 0.7 }
      ) do |gen|
        result = call_openai(messages)
        gen.output = result[:content]
        gen.usage = result[:usage]
        result[:content]
      end

      trace.output = { response: response }
      response
    end
  end

  private

  def call_openai(messages)
    # Your OpenAI implementation
  end
end
```

### In Models

```ruby
class Document < ApplicationRecord
  def summarize
    prompt = Langfuse.client.get_prompt(
      "document-summary",
      fallback: "Summarize this document: {{content}}",
      type: :text
    )

    prompt.compile(
      content: self.content,
      max_length: 500
    )
  end
end
```

### In Mailers

```ruby
class UserMailer < ApplicationMailer
  def welcome_email(user)
    prompt = Langfuse.client.get_prompt("welcome-email-template")

    @body = prompt.compile(
      user_name: user.name,
      verification_url: user_verification_url(user)
    )

    mail(to: user.email, subject: "Welcome!")
  end
end
```

## Background Jobs

### Sidekiq Integration

```ruby
class ProcessDocumentJob < ApplicationJob
  queue_as :default

  def perform(document_id, trace_context = nil)
    document = Document.find(document_id)

    # Continue trace from web request if context provided
    Langfuse.trace(
      name: "process-document-job",
      context: trace_context,
      metadata: { document_id: document_id, queue: :default }
    ) do |trace|
      trace.span(name: "extract-text") do |span|
        text = extract_text(document)
        span.output = { text_length: text.length }
      end

      trace.generation(name: "summarize", model: "gpt-4") do |gen|
        summary = generate_summary(text)
        gen.output = summary
        document.update!(summary: summary)
      end
    end
  end
end
```

### Enqueue with Trace Context

```ruby
class DocumentsController < ApplicationController
  def create
    Langfuse.trace(name: "document-upload") do |trace|
      document = Document.create!(document_params)

      # Extract trace context to pass to background job
      context = trace.inject_context
      ProcessDocumentJob.perform_later(document.id, context)

      trace.event(name: "job-enqueued", metadata: { document_id: document.id })

      render json: document, status: :created
    end
  end
end
```

### ActiveJob Configuration

For async tracing with ActiveJob:

```ruby
# config/initializers/langfuse.rb
Langfuse.configure do |config|
  # ... other config

  config.tracing_async = true  # Enable async processing
  config.job_queue = :langfuse  # Custom queue name (optional)
end
```

## Testing

### RSpec Configuration

```ruby
# spec/rails_helper.rb or spec/spec_helper.rb
RSpec.configure do |config|
  config.before(:each) do
    Langfuse.reset!  # Clear global state between tests
  end

  # Don't make real API calls in tests
  config.before(:each, type: :request) do
    allow_any_instance_of(Langfuse::Client).to receive(:get_prompt).and_call_original
  end
end
```

### Mocking Prompts

```ruby
# spec/support/langfuse_helpers.rb
module LangfuseHelpers
  def mock_langfuse_prompt(name, content, type: :text)
    allow_any_instance_of(Langfuse::Client)
      .to receive(:get_prompt)
      .with(name, any_args)
      .and_return(
        if type == :text
          Langfuse::TextPromptClient.new(
            "name" => name,
            "version" => 1,
            "type" => "text",
            "prompt" => content,
            "labels" => ["test"],
            "tags" => [],
            "config" => {}
          )
        else
          Langfuse::ChatPromptClient.new(
            "name" => name,
            "version" => 1,
            "type" => "chat",
            "prompt" => content,
            "labels" => ["test"],
            "tags" => [],
            "config" => {}
          )
        end
      )
  end
end

RSpec.configure do |config|
  config.include LangfuseHelpers
end
```

### Example Test

```ruby
# spec/services/ai_assistant_service_spec.rb
require 'rails_helper'

RSpec.describe AiAssistantService do
  let(:user) { create(:user, name: "Alice") }
  let(:service) { described_class.new(user) }

  before do
    mock_langfuse_prompt(
      "assistant-chat",
      [
        { "role" => "system", "content" => "You are an assistant for {{user_name}}" },
        { "role" => "user", "content" => "{{question}}" }
      ],
      type: :chat
    )
  end

  it "generates a response using the prompt" do
    allow(service).to receive(:call_openai).and_return({
      content: "Hello Alice!",
      usage: { prompt_tokens: 10, completion_tokens: 5 }
    })

    response = service.generate_response("What is Ruby?")

    expect(response).to eq("Hello Alice!")
  end
end
```

### Integration Tests

For integration tests that actually call the Langfuse API, use VCR:

```ruby
# Gemfile (test group)
gem 'vcr'
gem 'webmock'
```

```ruby
# spec/support/vcr.rb
require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter sensitive data
  config.filter_sensitive_data('<LANGFUSE_PUBLIC_KEY>') { ENV['LANGFUSE_PUBLIC_KEY'] }
  config.filter_sensitive_data('<LANGFUSE_SECRET_KEY>') { ENV['LANGFUSE_SECRET_KEY'] }
end
```

```ruby
# spec/integration/langfuse_api_spec.rb
require 'rails_helper'

RSpec.describe 'Langfuse API Integration', vcr: true do
  it 'fetches a real prompt from Langfuse' do
    prompt = Langfuse.client.get_prompt('greeting')

    expect(prompt).to be_a(Langfuse::TextPromptClient)
    expect(prompt.name).to eq('greeting')
  end
end
```

## Deployment

### Heroku

Add environment variables:

```bash
heroku config:set LANGFUSE_PUBLIC_KEY=pk_...
heroku config:set LANGFUSE_SECRET_KEY=sk_...
heroku config:set LANGFUSE_TRACING_ENABLED=true
```

### Docker

In your `Dockerfile` or `docker-compose.yml`:

```yaml
# docker-compose.yml
services:
  web:
    environment:
      - LANGFUSE_PUBLIC_KEY=${LANGFUSE_PUBLIC_KEY}
      - LANGFUSE_SECRET_KEY=${LANGFUSE_SECRET_KEY}
      - LANGFUSE_TRACING_ENABLED=true
```

### Kubernetes

Use Kubernetes secrets:

```yaml
# config/secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: langfuse-secrets
type: Opaque
data:
  public-key: <base64-encoded-key>
  secret-key: <base64-encoded-key>
```

```yaml
# deployment.yaml
env:
  - name: LANGFUSE_PUBLIC_KEY
    valueFrom:
      secretKeyRef:
        name: langfuse-secrets
        key: public-key
  - name: LANGFUSE_SECRET_KEY
    valueFrom:
      secretKeyRef:
        name: langfuse-secrets
        key: secret-key
  - name: LANGFUSE_TRACING_ENABLED
    value: "true"
```

### Health Checks

Add a health check endpoint that verifies Langfuse connectivity:

```ruby
# config/routes.rb
get '/health/langfuse', to: 'health#langfuse'

# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def langfuse
    # Try to fetch a test prompt
    Langfuse.client.get_prompt('health-check', fallback: "OK", type: :text)

    render json: { status: 'ok', service: 'langfuse' }
  rescue => e
    render json: { status: 'error', service: 'langfuse', error: e.message }, status: :service_unavailable
  end
end
```

### Graceful Shutdown

Ensure traces are flushed on shutdown:

```ruby
# config/initializers/langfuse.rb (at the end)
at_exit do
  Langfuse.shutdown(timeout: 10)
end
```

## Best Practices

### 1. Use Environment-Specific Labels

```ruby
# Fetch prompts by environment
prompt = Langfuse.client.get_prompt("greeting", label: Rails.env)

# Or use conditional logic
label = Rails.env.production? ? "production" : "development"
prompt = Langfuse.client.get_prompt("greeting", label: label)
```

### 2. Always Provide Fallbacks in Production

```ruby
# config/initializers/langfuse.rb
fallback_enabled = Rails.env.production?

# In your code
prompt = Langfuse.client.get_prompt(
  "greeting",
  fallback: fallback_enabled ? "Hello {{name}}!" : nil,
  type: fallback_enabled ? :text : nil
)
```

### 3. Cache Prompts Aggressively in Production

```ruby
Langfuse.configure do |config|
  # Long cache in production, short in development
  config.cache_ttl = Rails.env.production? ? 600 : 30  # 10 min vs 30 sec
end
```

### 4. Use Service Objects for Complex LLM Logic

Instead of putting LLM logic in controllers:

```ruby
# Good: Service object
class ChatService
  def initialize(user)
    @user = user
  end

  def generate_response(message)
    # Complex logic here
  end
end

# In controller
class ChatsController < ApplicationController
  def create
    service = ChatService.new(current_user)
    response = service.generate_response(params[:message])
    render json: { response: response }
  end
end
```

### 5. Log Prompt Fetches in Development

```ruby
# config/environments/development.rb
config.after_initialize do
  Rails.logger.info "Langfuse configured with cache_ttl: #{Langfuse.configuration.cache_ttl}"
end
```

### 6. Monitor Cache Hit Rates

Add instrumentation to track cache effectiveness:

```ruby
# app/middleware/langfuse_metrics.rb
class LangfuseMetrics
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)

    # Log cache stats
    if Langfuse.client.respond_to?(:cache_stats)
      Rails.logger.info("Langfuse cache stats: #{Langfuse.client.cache_stats}")
    end

    [status, headers, response]
  end
end
```

### 7. Use Tracing for LLM Observability

```ruby
# Always wrap LLM calls in traces for observability
def generate_content(prompt_text)
  Langfuse.trace(name: "generate-content", user_id: current_user.id) do |trace|
    trace.generation(name: "openai", model: "gpt-4") do |gen|
      result = call_openai(prompt_text)
      gen.output = result
      result
    end
  end
end
```

### 8. Handle Rate Limits Gracefully

```ruby
def fetch_prompt_with_retry(name, max_retries: 3)
  retries = 0

  begin
    Langfuse.client.get_prompt(name)
  rescue Langfuse::ApiError => e
    retries += 1
    if retries < max_retries
      sleep(2 ** retries)  # Exponential backoff
      retry
    else
      # Use fallback
      Rails.logger.error("Langfuse API failed after #{max_retries} retries: #{e.message}")
      return fallback_prompt(name)
    end
  end
end
```

### 9. Organize Prompts by Feature

Use naming conventions:

```
# Good naming structure
feature-action-context
  - email-welcome-user
  - email-reset-password
  - chat-support-greeting
  - chat-support-farewell
  - summary-document-short
  - summary-document-detailed
```

### 10. Test Prompt Compilation Separately

```ruby
# spec/prompts/greeting_prompt_spec.rb
RSpec.describe 'Greeting Prompt' do
  it 'compiles correctly with all variables' do
    prompt = mock_langfuse_prompt('greeting', 'Hello {{name}}!')

    result = prompt.compile(name: 'Alice')

    expect(result).to eq('Hello Alice!')
  end

  it 'handles missing variables gracefully' do
    prompt = mock_langfuse_prompt('greeting', 'Hello {{name}}!')

    # Mustache renders empty string for missing variables
    result = prompt.compile({})

    expect(result).to eq('Hello !')
  end
end
```

## Troubleshooting

### Prompts Not Updating

If prompts aren't updating after changes in Langfuse:

1. **Check cache TTL**: Prompts are cached. Wait for TTL to expire or restart server
2. **Clear cache manually**: `Langfuse.client.instance_variable_get(:@api_client).cache&.clear` (in console)
3. **Reduce cache TTL in development**: `config.cache_ttl = 10` for faster iteration

### Authentication Errors

```ruby
# Verify credentials are loaded
Rails.application.console do
  puts "Public Key: #{Langfuse.configuration.public_key}"
  puts "Secret Key: #{Langfuse.configuration.secret_key&.slice(0, 8)}..."
end
```

### High Latency

If prompt fetches are slow:

1. **Enable caching**: Ensure `cache_ttl > 0`
2. **Use fallbacks**: Provide fallback prompts for critical paths
3. **Warm cache on boot**: Fetch frequently-used prompts in initializer

### Memory Issues

If experiencing high memory usage:

1. **Reduce cache_max_size**: Default is 1000, reduce if needed
2. **Enable cache cleanup**: Implement periodic cache cleanup in background job

## Additional Resources

- [Main README](../README.md) - SDK overview and basic usage
- [Tracing Guide](TRACING.md) - Deep dive on LLM tracing
- [Migration Guide](MIGRATION.md) - Migrating from hardcoded prompts
- [Langfuse Documentation](https://langfuse.com/docs) - Official Langfuse docs
