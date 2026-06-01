.PHONY: help setup smoke ingress lint
.DEFAULT_GOAL := help

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-10s %s\n", $$1, $$2}'

setup: ## One-time dev setup (install the git hooks; docs/ is a separate private repo)
	git config core.hooksPath .githooks
	@echo "Hooks installed. If you need the private docs, clone them into docs/:"
	@echo "  git clone git@github.com:bonzanni/hindsight-ha-app-docs.git docs"

smoke: ## Build + boot smoke test (needs OPENROUTER_KEY in the environment)
	tests/smoke.sh

ingress: ## Playwright ingress UI test (needs OPENROUTER_KEY; runs the browser in Docker)
	tests/run-ingress.sh

lint: ## hadolint the Dockerfile + shellcheck the s6/test scripts (via Docker)
	docker run --rm -i hadolint/hadolint hadolint \
	  --ignore DL3008 --ignore DL3006 --ignore DL3007 --ignore DL4006 --ignore DL3059 \
	  - < hindsight/Dockerfile
	docker run --rm -v "$$PWD":/src -w /src koalaman/shellcheck:stable -s bash -e SC1008 \
	  $$(find hindsight/rootfs/etc/s6-overlay -type f \( -name '*.sh' -o -name run -o -name finish -o -name up \)) \
	  tests/smoke.sh tests/run-ingress.sh
