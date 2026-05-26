.PHONY: help build test test-full format release publish-release push-and-publish docker-build clean version

BOT_NAME := bridge_lite

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: ## Compile the project
	mix deps.get && mix compile

test: ## Run unit tests (excludes integration)
	mix test --exclude integration

test-full: ## Run all tests including integration
	mix test --include integration --trace

format: ## Format code
	mix format

release: ## Build OTP release
	MIX_ENV=prod mix release --overwrite

publish-release: release ## Build, package, and publish to GitHub
	@echo "==============================================="
	@echo "Publishing release to GitHub"
	@echo "==============================================="
	@echo ""
	@set -e; \
	VERSION=$$(sed -n 's/^.*@version[[:space:]]*"\([^"]*\)".*/\1/p' mix.exs | head -n 1); \
	if [ -z "$$VERSION" ]; then \
		echo "Failed to resolve version from mix.exs"; \
		exit 1; \
	fi; \
	TARBALL=$(BOT_NAME)-$$VERSION.tar.gz; \
	echo "Version: $$VERSION"; \
	echo "Creating release tarball..."; \
	tar -czf "$$TARBALL" -C _build/prod/rel $(BOT_NAME)/; \
	echo "✓ Tarball created: $$TARBALL"; \
	echo ""; \
	echo "Creating GitHub release v$$VERSION..."; \
	if gh release view "v$$VERSION" >/dev/null 2>&1; then \
		gh release upload "v$$VERSION" "$$TARBALL" --clobber; \
	else \
		gh release create "v$$VERSION" "$$TARBALL" --title "v$$VERSION" --notes "Release v$$VERSION"; \
	fi; \
	echo ""; \
	echo "✓ Published v$$VERSION"; \
	rm -f "$$TARBALL"

push-and-publish: ## Push then publish release asset
	git push && $(MAKE) publish-release

docker-build: ## Build Docker image
	docker build -t ergon-automation-labs/$(BOT_NAME):latest .

clean: ## Clean build artifacts
	mix clean && rm -rf _build deps

version: ## Show current version
	mix run -e "IO.puts Mix.Project.config()[:version]"