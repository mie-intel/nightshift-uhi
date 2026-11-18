# NightShift — common commands (README §20). Contracts live in contracts/.
.DEFAULT_GOAL := help
C := contracts
SHELL := /bin/bash

.PHONY: help install build build-reactive test test-scenarios coverage slither fmt fmt-check \
        deploy-testnet fund-reactive e2e-testnet record report app check-context

help: ## list targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-16s %s\n",$$1,$$2}'

install: ## forge + pnpm deps
	cd $(C) && forge install
	@command -v pnpm >/dev/null && pnpm install || echo "pnpm not found — skipping JS deps"

build: ## forge build (default profile)
	cd $(C) && forge build

build-reactive: ## forge build (reactive profile, solc 0.8.29)
	cd $(C) && FOUNDRY_PROFILE=reactive forge build

test: ## forge test -vvv
	cd $(C) && forge test -vvv

test-scenarios: ## scenario replays → docs/recordings/scenarios.csv (Phase 10)
	cd $(C) && forge test --match-path "test/scenarios/*" -vv

coverage: ## forge coverage (lcov)
	cd $(C) && forge coverage --report lcov

slither: ## static analysis (Phase 14)
	cd $(C) && slither .

fmt: ## forge fmt
	cd $(C) && forge fmt

fmt-check: ## forge fmt --check (CI)
	cd $(C) && forge fmt --check

check-context: ## verify @imports in CLAUDE.md + .claude/rules
	./scripts/check-context.sh

deploy-testnet: ## scripts 00-05 (Phase 4+)
	@echo "deploy-testnet not implemented yet (Phase 4+). See TODO.md." && exit 1

fund-reactive: ## lREACT faucet + top-up (Phase 4)
	@echo "fund-reactive not implemented yet (Phase 4). See TODO.md." && exit 1

e2e-testnet: ## trigger witness move + await callback (Phase 4)
	@echo "e2e-testnet not implemented yet (Phase 4). See TODO.md." && exit 1

record: ## start recorder, all chains (Phase 12)
	@echo "record not implemented yet (Phase 12). See TODO.md." && exit 1

report: ## generate report JSON/CSV (Phase 12)
	@echo "report not implemented yet (Phase 12). See TODO.md." && exit 1

app: ## run dashboard dev server (Phase 13)
	@echo "app not implemented yet (Phase 13). See TODO.md." && exit 1
