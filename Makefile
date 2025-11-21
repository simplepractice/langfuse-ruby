.DEFAULT_GOAL := help

.PHONY: help test lint fix console build install clean check

BLUE := \033[34m
WHITE := \033[37m
GRAY := \033[90m
RESET := \033[0m

help:
	@echo ""
	@echo "  $(BLUE)🪢  Langfuse Ruby SDK$(RESET)"
	@echo ""
	@echo "  $(WHITE)make test$(RESET)      $(GRAY)Run RSpec test suite$(RESET)"
	@echo "  $(WHITE)make lint$(RESET)      $(GRAY)Run RuboCop linter$(RESET)"
	@echo "  $(WHITE)make fix$(RESET)       $(GRAY)Auto-fix RuboCop violations$(RESET)"
	@echo "  $(WHITE)make check$(RESET)     $(GRAY)Run tests + lint (CI check)$(RESET)"
	@echo "  $(WHITE)make console$(RESET)   $(GRAY)Open interactive Ruby console$(RESET)"
	@echo "  $(WHITE)make build$(RESET)     $(GRAY)Build the gem$(RESET)"
	@echo "  $(WHITE)make install$(RESET)   $(GRAY)Install gem locally$(RESET)"
	@echo "  $(WHITE)make clean$(RESET)     $(GRAY)Remove generated files$(RESET)"
	@echo "  $(WHITE)make setup$(RESET)     $(GRAY)Install dependencies$(RESET)"
	@echo ""

test:
	bundle exec rspec

lint:
	bundle exec rubocop

fix:
	bundle exec rubocop -A

check: test lint

console:
	bundle exec irb -r ./lib/langfuse

build:
	gem build langfuse.gemspec

install: build
	gem install langfuse-*.gem

clean:
	rm -f langfuse-*.gem
	rm -rf coverage/
	rm -rf pkg/

setup:
	bundle install
