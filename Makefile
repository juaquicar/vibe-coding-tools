# vibe-coding-tools — developer tasks
SHELL := bash
.SHELLFLAGS := -Eeuo pipefail -c
.DEFAULT_GOAL := help

ROOT      := $(shell pwd)
SHELLSRC  := $(shell find . -type f \( -name '*.sh' -o -path './bin/*' \) -not -path './.git/*' | sort)

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: bootstrap
bootstrap: ## Install the irreducible prerequisites (jq, git, curl, python3)
	@./bootstrap.sh

.PHONY: manifest
manifest: ## Compile components.yaml -> components.json
	@python3 scripts/compile-manifest.py

.PHONY: manifest-check
manifest-check: ## Fail if the committed JSON is stale
	@python3 scripts/compile-manifest.py --check

.PHONY: install
install: manifest ## Install the developer profile
	@./install.sh --profile developer

.PHONY: update
update: ## Update vibe-coding-tools and every installed component
	@./update.sh

.PHONY: doctor
doctor: ## Run the health matrix
	@./bin/aistack doctor

.PHONY: reset
reset: ## Preview a reset of global agent extensions
	@./reset.sh

.PHONY: shellcheck
shellcheck: ## Static analysis of every shell script
	@command -v shellcheck >/dev/null || { echo "shellcheck not installed: sudo apt-get install shellcheck"; exit 1; }
	@shellcheck --external-sources --source-path=$(ROOT) $(SHELLSRC)
	@echo "shellcheck: clean"

.PHONY: shfmt
shfmt: ## Check shell formatting
	@command -v shfmt >/dev/null || { echo "shfmt not installed: go install mvdan.cc/sh/v3/cmd/shfmt@latest"; exit 1; }
	@shfmt -d -i 2 -ci -bn $(SHELLSRC)

.PHONY: fmt
fmt: ## Reformat every shell script in place
	@shfmt -w -i 2 -ci -bn $(SHELLSRC)

.PHONY: lint
lint: manifest-check shellcheck ## Everything CI checks before tests

.PHONY: test
test: ## Run the bats test suite
	@./tests/run.sh

.PHONY: ci
ci: lint test ## The full CI pipeline, locally

.PHONY: clean
clean: ## Remove build artefacts and local caches
	@rm -rf .pytest_cache **/__pycache__ tests/tmp
	@echo "cleaned"

.PHONY: release
release: ci ## Tag a release (VERSION=x.y.z make release)
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=1.2.3"; exit 1; }
	@grep -q 'AI_VERSION="$(VERSION)"' lib/version.sh || { echo "bump AI_VERSION in lib/version.sh first"; exit 1; }
	@grep -q '## \[$(VERSION)\]' CHANGELOG.md || { echo "add a $(VERSION) section to CHANGELOG.md first"; exit 1; }
	@git tag -a "v$(VERSION)" -m "vibe-coding-tools v$(VERSION)"
	@echo "tagged v$(VERSION) — push with: git push origin v$(VERSION)"
