.PHONY: help setup smoke ingress contracts lint apparmor
.DEFAULT_GOAL := help

APPARMOR_PROFILE ?= hindsight/apparmor.txt
APPARMOR_PARSER ?= apparmor_parser

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-10s %s\n", $$1, $$2}'

setup: ## One-time dev setup (install the git hooks; docs/ is a separate private repo)
	git config core.hooksPath .githooks
	@echo "Hooks installed. If you need the private docs, clone them into docs/:"
	@echo "  git clone git@github.com:bonzanni/ha-hindsight-app-docs.git docs"

smoke: ## Build + boot smoke test (needs OPENROUTER_KEY in the environment)
	tests/smoke.sh

ingress: ## Playwright ingress UI test (needs OPENROUTER_KEY; runs the browser in Docker)
	tests/run-ingress.sh

contracts: ## Run fast packaging, harness, and release-doc contract checks (no Docker required)
	tests/packaging-contract.sh
	tests/docs-release-contract.sh

lint: contracts apparmor ## hadolint the Dockerfile + shellcheck the s6/test scripts + validate apparmor
	docker run --rm -i hadolint/hadolint hadolint \
	  --ignore DL3008 --ignore DL3006 --ignore DL3007 --ignore DL4006 --ignore DL3059 \
	  - < hindsight/Dockerfile
	docker run --rm -v "$$PWD":/src -w /src koalaman/shellcheck:stable -s bash -e SC1008 \
	  $$(find hindsight/rootfs/etc/s6-overlay -type f \( -name '*.sh' -o -name run -o -name finish -o -name up \)) \
	  tests/smoke.sh tests/run-ingress.sh tests/packaging-contract.sh tests/docs-release-contract.sh tests/lib/test-image.sh

apparmor: ## Validate apparmor.txt: one signal rule must permit send and receive, and it must parse
	@awk '\
	  /^[[:space:]]*signal/ { \
	    line = $$0; sub(/#.*/, "", line); \
	    has_send = line ~ /(^|[^[:alnum:]_])send([^[:alnum:]_]|$$)/; \
	    has_receive = line ~ /(^|[^[:alnum:]_])receive([^[:alnum:]_]|$$)/; \
	    if (has_send && has_receive) found = 1; \
	  } \
	  END { exit(found ? 0 : 1) }' "$(APPARMOR_PROFILE)" \
	  || { echo "FAIL: $(APPARMOR_PROFILE) signal rule must permit both 'send' and 'receive'"; exit 1; }
	@if command -v "$(APPARMOR_PARSER)" >/dev/null 2>&1; then \
	  "$(APPARMOR_PARSER)" -QK "$(APPARMOR_PROFILE)" >/dev/null && echo "$(APPARMOR_PROFILE): send+receive OK, syntax OK"; \
	else \
	  echo "$(APPARMOR_PROFILE): send+receive OK ($(APPARMOR_PARSER) absent; syntax check skipped)"; \
	fi
