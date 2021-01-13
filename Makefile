install: install-unit-test-deps

install-unit-test-deps:
	./hack/make-rules/install-unit-test-deps.sh

unit-test:
	./hack/make-rules/unit-test.sh

.PHONY: verify
verify: ## Verify that dev dependencies are installed and correctly configured
	./hack/make-rules/verify.sh