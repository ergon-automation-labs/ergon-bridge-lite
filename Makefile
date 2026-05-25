.PHONY: help build test test-full format release docker-build clean

BOT_NAME := bridge_lite
APP_NAME := bot_army_bridge_lite

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: ## Compile the project
	cd $(APP_NAME) && mix deps.get && mix compile

test: ## Run unit tests (excludes integration)
	cd $(APP_NAME) && mix test --exclude integration

test-full: ## Run all tests including integration
	cd $(APP_NAME) && mix test --include integration --trace

format: ## Format code
	cd $(APP_NAME) && mix format

release: ## Build OTP release
	cd $(APP_NAME) && MIX_ENV=prod mix release --overwrite

docker-build: ## Build Docker image (run from monorepo root)
	docker build -t ergon-automation-labs/$(BOT_NAME):latest -f $(APP_NAME)/Dockerfile .

clean: ## Clean build artifacts
	cd $(APP_NAME) && mix clean && rm -rf _build deps

version: ## Show current version
	cd $(APP_NAME) && mix run -e "IO.puts Mix.Project.config()[:version]"