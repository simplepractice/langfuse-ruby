# frozen_string_literal: true

require_relative "lib/langfuse/version"

Gem::Specification.new do |spec|
  spec.name = "langfuse"
  spec.version = Langfuse::VERSION
  spec.authors = ["Langfuse"]
  spec.email = ["developers@langfuse.com"]

  spec.summary = "Ruby SDK for Langfuse - LLM observability and prompt management"
  spec.description = "Official Ruby SDK for Langfuse, providing LLM tracing, observability, " \
                     "and prompt management capabilities"
  spec.homepage = "https://github.com/langfuse/langfuse-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/langfuse/langfuse-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/langfuse/langfuse-ruby/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob(%w[
                          lib/**/*.rb
                          README.md
                          LICENSE
                          CHANGELOG.md
                        ])
  spec.require_paths = ["lib"]

  # Runtime dependencies - HTTP & Templating
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-retry", "~> 2.0"
  spec.add_dependency "mustache", "~> 1.1"

  # Runtime dependencies - OpenTelemetry (for tracing)
  spec.add_dependency "opentelemetry-api", "~> 1.2"
  spec.add_dependency "opentelemetry-common", "~> 0.21"
  spec.add_dependency "opentelemetry-sdk", "~> 1.4"

  # Development dependencies are specified in Gemfile
end
