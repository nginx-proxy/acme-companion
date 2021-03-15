.DEFAULT_GOAL := help

.PHONY: help
help: ## Show help
#	Source: https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: install
install: install-unit-test-deps ## Install all dev dependencies

.PHONY: install-unit-test-deps
install-unit-test-deps:
	./hack/make-rules/install-unit-test-deps.sh

.PHONY: unit-test
unit-test: ## Run all tests
	./hack/make-rules/unit-test.sh

.PHONY: verify
verify: ## Verify that dev dependencies are installed and correctly configured
	./hack/make-rules/verify.sh