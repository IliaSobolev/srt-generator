# Developer entry points. `make ci` is the definition of done (see CLAUDE.md).
SHELL := /bin/zsh
TOOLS := .tools/bin
SWIFTLINT := $(TOOLS)/swiftlint
SWIFTFORMAT := $(TOOLS)/swiftformat
ACTIONLINT := $(TOOLS)/actionlint
CLEAN_OUT := sed 's/\x1b\[[0-9;]*m//g'

.PHONY: help tools build test lint format coverage policy ci actionlint app dmg release mutate secrets clean

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

tools: ## Download pinned, checksum-verified swiftlint/swiftformat/actionlint/gitleaks into .tools/bin
	@scripts/bootstrap-tools.sh

$(SWIFTLINT) $(SWIFTFORMAT) $(ACTIONLINT):
	@scripts/bootstrap-tools.sh swiftlint swiftformat actionlint

build: ## Debug build of every target incl. tests (warnings are errors via Package.swift)
	@set -o pipefail; swift build --build-tests 2>&1 | $(CLEAN_OUT) | grep -E 'error:|warning:|Build complete' | grep -v '/.build/checkouts/'

test: ## Run the unit tests
	@set -o pipefail; swift test 2>&1 | $(CLEAN_OUT) | grep -E "✘|error:|Test run with|recorded an issue"

lint: $(SWIFTLINT) $(SWIFTFORMAT) ## SwiftFormat (check only) and SwiftLint --strict
	@$(SWIFTFORMAT) --lint --quiet .
	@$(SWIFTLINT) lint --quiet --strict

format: $(SWIFTFORMAT) $(SWIFTLINT) ## Auto-format and apply safe lint fixes
	@$(SWIFTFORMAT) --quiet .
	@$(SWIFTLINT) lint --fix --quiet

coverage: ## Tests with coverage; fails if SRTCore line coverage < COVERAGE_MIN (default 100)
	@scripts/coverage.sh

policy: ## Network policy check (APIs, hosts, entitlements, dependencies)
	@scripts/check-network-policy.sh

actionlint: $(ACTIONLINT) ## Validate GitHub Actions workflows
	@$(ACTIONLINT)

ci: lint build coverage policy ## Everything CI runs (coverage includes the tests)
	@[[ -d .github/workflows ]] && $(ACTIONLINT) || true
	@echo "make ci: all checks passed"

app: ## Build dist/SRT Generator.app (release, ad-hoc signed)
	@./build-app.sh

dmg: app ## Build dist/SRTGenerator-<VERSION>.dmg and its .sha256
	@scripts/make-dmg.sh

release: ## Cut a release: make release VERSION=X.Y.Z [DRY_RUN=1]
	@scripts/release.sh "$(VERSION)"

mutate: ## Mutation testing on SRTCore (slow; on demand only, not in CI)
	@scripts/mutate.sh

secrets: ## Scan the whole git history for secrets (gitleaks) and large files
	@scripts/scan-history.sh

clean: ## Remove build products
	@swift package clean && rm -rf dist
