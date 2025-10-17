# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
namespace :langfuse do
  desc "Warm the Langfuse prompt cache with specified prompts"
  task :warm_cache, [:prompts] => :environment do |_t, args|
    require "langfuse"

    # Get prompts from args or environment variable
    prompts = if args[:prompts]
                args[:prompts].split(",")
              else
                ENV.fetch("LANGFUSE_PROMPTS_TO_WARM", "").split(",")
              end

    if prompts.empty?
      puts "Usage: rake langfuse:warm_cache[prompt1,prompt2,prompt3]"
      puts "   or: LANGFUSE_PROMPTS_TO_WARM=prompt1,prompt2 rake langfuse:warm_cache"
      exit 1
    end

    # Clean up whitespace
    prompts.map!(&:strip)

    puts "Warming cache for #{prompts.size} prompt(s)..."
    puts "Cache backend: #{Langfuse.configuration.cache_backend}"
    puts ""

    client = Langfuse.client
    results = { success: [], failed: [] }

    prompts.each do |name|
      print "Fetching '#{name}'... "
      begin
        prompt = client.get_prompt(name)
        results[:success] << name
        puts "✓ (#{prompt.class.name.split('::').last}, version #{prompt.version})"
      rescue Langfuse::NotFoundError
        results[:failed] << { name: name, error: "Not found" }
        puts "✗ Not found"
      rescue Langfuse::UnauthorizedError
        results[:failed] << { name: name, error: "Unauthorized - check API keys" }
        puts "✗ Unauthorized"
      rescue Langfuse::ApiError => e
        results[:failed] << { name: name, error: e.message }
        puts "✗ API error: #{e.message}"
      rescue StandardError => e
        results[:failed] << { name: name, error: e.message }
        puts "✗ Error: #{e.message}"
      end
    end

    puts ""
    display_warming_results(results, prompts.size)
  end

  desc "Warm the cache with ALL prompts (auto-discovery)"
  task warm_cache_all: :environment do
    require "langfuse"

    puts "Auto-discovering prompts from Langfuse..."
    puts "Cache backend: #{Langfuse.configuration.cache_backend}"
    puts ""

    warmer = Langfuse::CacheWarmer.new

    begin
      # Fetch all prompts
      prompt_list = warmer.client.list_prompts
      prompt_names = prompt_list.map { |p| p["name"] }.uniq

      if prompt_names.empty?
        puts "No prompts found in your Langfuse project."
        exit 0
      end

      puts "Found #{prompt_names.size} unique prompt(s)"
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts ""

      # Warm cache with all prompts
      results = warmer.warm_all

      # Display results
      results[:success].each do |name|
        puts "✓ #{name}"
      end

      results[:failed].each do |failure|
        puts "✗ #{failure[:name]}: #{failure[:error]}"
      end

      puts ""
      display_warming_results(results, prompt_names.size)
    rescue Langfuse::UnauthorizedError
      puts "✗ Authentication failed. Check your API keys."
      exit 1
    rescue Langfuse::ApiError => e
      puts "✗ API error: #{e.message}"
      exit 1
    rescue StandardError => e
      puts "✗ Error: #{e.message}"
      exit 1
    end
  end

  desc "List all prompts (requires LANGFUSE_PROMPT_NAMES environment variable)"
  task list_prompts: :environment do
    require "langfuse"

    prompt_names = ENV.fetch("LANGFUSE_PROMPT_NAMES", "").split(",").map(&:strip)

    if prompt_names.empty?
      puts "Set LANGFUSE_PROMPT_NAMES environment variable with comma-separated prompt names"
      puts "Example: LANGFUSE_PROMPT_NAMES=greeting,conversation rake langfuse:list_prompts"
      exit 1
    end

    client = Langfuse.client
    puts "Langfuse Prompts"
    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    puts ""

    prompt_names.each do |name|
      prompt = client.get_prompt(name)
      puts "#{prompt.name} (v#{prompt.version})"
      puts "  Type: #{prompt.class.name.split('::').last}"
      puts "  Labels: #{prompt.labels.join(', ')}" if prompt.labels.any?
      puts "  Tags: #{prompt.tags.join(', ')}" if prompt.tags.any?
      puts ""
    rescue Langfuse::NotFoundError
      puts "#{name} - NOT FOUND"
      puts ""
    rescue StandardError => e
      puts "#{name} - ERROR: #{e.message}"
      puts ""
    end
  end

  desc "Clear the Langfuse prompt cache"
  task clear_cache: :environment do
    require "langfuse"

    cache = Langfuse.client.api_client.cache

    if cache.nil?
      puts "Cache is disabled (cache_ttl = 0)"
      exit 0
    end

    if cache.respond_to?(:clear)
      cache.clear
      puts "Cache cleared successfully! ✓"
      puts "Backend: #{Langfuse.configuration.cache_backend}"
    else
      puts "Cache backend does not support clearing"
      exit 1
    end
  end

  # Helper method to display warming results
  def display_warming_results(results, total)
    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    puts "Cache Warming Results"
    puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    puts "✓ Success: #{results[:success].size}/#{total}"
    puts "✗ Failed:  #{results[:failed].size}/#{total}"

    puts ""
    if results[:failed].any?
      puts "Failed prompts:"
      results[:failed].each do |failure|
        puts "  - #{failure[:name]}: #{failure[:error]}"
      end
      exit 1
    else
      puts "All prompts cached successfully! 🎉"
    end
  end
end
# rubocop:enable Metrics/BlockLength
