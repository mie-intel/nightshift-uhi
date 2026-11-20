# NightShift — common commands (README §20). Contracts live in contracts/.
.DEFAULT_GOAL := help
C := contracts
SHELL := /bin/bash

.PHONY: help install build build-reactive test test-scenarios coverage slither fmt fmt-check \
        deploy-testnet deploy-origin deploy-dest deploy-reactive deploy-controller wire-reactive \
        fund-reactive e2e-testnet record report app check-context

# Load .env (never committed) into recipe shells. Override per-chain forge flags if a chain needs e.g. --legacy.
ENV := set -a; [ -f .env ] && . ./.env; set +a;
LASNA_FLAGS ?=
# Sepolia's current gas schedule prices CREATE far above forge's local simulation (~6.6x: node 4.69M vs local 0.71M for a token),
# so origin txs need a larger estimate multiplier. Gas price there is ~0, so this costs nothing extra.
ORIGIN_FLAGS ?= --gas-estimate-multiplier 1000 --slow
REACTIVE_BUILD := FOUNDRY_PROFILE=reactive
REACTIVE_SKIP := --skip "*/V4Artifacts.sol" --skip "*/01_DeployDestination.s.sol"

help: ## list targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-18s %s\n",$$1,$$2}'

install: ## forge + pnpm deps
	cd $(C) && forge install
	@command -v pnpm >/dev/null && pnpm install || echo "pnpm not found — skipping JS deps"

build: ## forge build (default profile)
	cd $(C) && forge build

build-reactive: ## forge build (reactive profile, solc 0.8.29)
	cd $(C) && $(REACTIVE_BUILD) forge build $(REACTIVE_SKIP)

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

deploy-testnet: deploy-origin deploy-dest deploy-reactive deploy-controller wire-reactive ## full testnet deploy (00-04) → deployments/testnet.json

deploy-origin: ## 00: demo tokens + MockIssuer on Ethereum Sepolia
	$(ENV) cd $(C) && forge script script/00_DeployOrigin.s.sol --rpc-url $$RPC_ETH_SEPOLIA --broadcast $(ORIGIN_FLAGS)

deploy-dest: ## 01: tokens, mined hook, pool, routers, liquidity on Base Sepolia
	$(ENV) cd $(C) && forge script script/01_DeployDestination.s.sol --rpc-url $$RPC_BASE_SEPOLIA --broadcast

deploy-reactive: ## 02: NightShiftReactive on Lasna (funded with lREACT)
	$(ENV) cd $(C) && $(REACTIVE_BUILD) forge script script/02_DeployReactive.s.sol $(REACTIVE_SKIP) --rpc-url $$RPC_LASNA --broadcast $(LASNA_FLAGS)

deploy-controller: ## 03: Controller on Base Sepolia + hook.initController
	$(ENV) cd $(C) && forge script script/03_DeployController.s.sol --rpc-url $$RPC_BASE_SEPOLIA --broadcast

wire-reactive: ## 04: reactive.setController + subscribe (Lasna)
	$(ENV) cd $(C) && $(REACTIVE_BUILD) forge script script/04_WireReactive.s.sol $(REACTIVE_SKIP) --rpc-url $$RPC_LASNA --broadcast $(LASNA_FLAGS)

fund-reactive: ## get lREACT on Lasna: send LREACT_ETH (default 0.05ether) Base Sepolia ETH to the faucet (1 ETH = 100 lREACT)
	$(ENV) cast send $$LREACT_FAUCET_BASE_SEPOLIA --value $${LREACT_ETH:-0.05ether} --rpc-url $$RPC_BASE_SEPOLIA --private-key $$REACTIVE_PRIVATE_KEY

e2e-testnet: ## 05: issuer price +MOVE_BPS (default 200) + mint on Sepolia → expect Lasna react + Base Sepolia callback
	$(ENV) cd $(C) && forge script script/05_TriggerIssuerMint.s.sol --rpc-url $$RPC_ETH_SEPOLIA --broadcast $(ORIGIN_FLAGS)

record: ## start recorder, all chains (Phase 12)
	@echo "record not implemented yet (Phase 12). See TODO.md." && exit 1

report: ## generate report JSON/CSV (Phase 12)
	@echo "report not implemented yet (Phase 12). See TODO.md." && exit 1

app: ## run dashboard dev server (Phase 13)
	@echo "app not implemented yet (Phase 13). See TODO.md." && exit 1
