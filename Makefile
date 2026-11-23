# NightShift — common commands (README §20). Contracts live in contracts/.
.DEFAULT_GOAL := help
C := contracts
SHELL := /bin/bash

.PHONY: help install build build-reactive test test-scenarios coverage slither fmt fmt-check \
        deploy-testnet deploy-origin deploy-dest deploy-reactive deploy-controller wire-reactive deploy-faucet deploy-vaults app-build news \
        fund-reactive e2e-testnet record report app check-context

# Load .env (never committed) into recipe shells. Override per-chain forge flags if a chain needs e.g. --legacy.
ENV := set -a; [ -f .env ] && . ./.env; set +a;
# Lasna RPC caps a tx fee at 1 lREACT; forge's default max fee (2x base) can exceed it on big deploys → pin 100 gwei.
LASNA_FLAGS ?= --with-gas-price 100gwei --priority-gas-price 1gwei
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

test-scenarios: ## scenario replays (static vs Gapguard-style vs NightShift) → docs/recordings/scenarios.csv
	@mkdir -p docs/recordings && echo "scenario,pool,swaps_filled,swaps_blocked,lp_pnl_vs_hodl_bps,avg_fee_bps,gap_at_reopen_ticks,max_premium_ticks" > docs/recordings/scenarios.csv
	cd $(C) && WRITE_SCENARIOS=true forge test --match-path "test/scenarios/*" -vv
	@{ head -1 docs/recordings/scenarios.csv; tail -n +2 docs/recordings/scenarios.csv | sort; } > docs/recordings/scenarios.csv.tmp && mv docs/recordings/scenarios.csv.tmp docs/recordings/scenarios.csv

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

deploy-testnet: deploy-origin deploy-dest deploy-faucet deploy-reactive deploy-controller deploy-vaults wire-reactive ## full testnet deploy → deployments/testnet.json

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

deploy-vaults: ## 08: VaultFactory + 3 demo curator vaults with seed deposits (Base Sepolia)
	$(ENV) cd $(C) && forge script script/08_DeployVaults.s.sol --rpc-url $$RPC_BASE_SEPOLIA --broadcast

deploy-faucet: ## 06: public demo-token faucet on Base Sepolia (for dashboard swaps)
	$(ENV) cd $(C) && forge script script/06_DeployFaucet.s.sol --rpc-url $$RPC_BASE_SEPOLIA --broadcast

news: ## demo "weekend news": issuer → PRICE (raw dUSD/share, e.g. 104000000) on Sepolia + sibling pool on Base
	$(ENV) cd $(C) && PRICE=$${PRICE:?set PRICE e.g. 104000000} forge script script/05_TriggerIssuerMint.s.sol --rpc-url $$RPC_ETH_SEPOLIA --broadcast $(ORIGIN_FLAGS)
	$(ENV) cd $(C) && PRICE=$$PRICE forge script script/07_MoveSibling.s.sol --rpc-url $$RPC_BASE_SEPOLIA --broadcast

fund-reactive: ## get lREACT on Lasna: send LREACT_ETH (default 0.05ether) Base Sepolia ETH to the faucet (1 ETH = 100 lREACT)
	$(ENV) cast send $$LREACT_FAUCET_BASE_SEPOLIA --value $${LREACT_ETH:-0.05ether} --rpc-url $$RPC_BASE_SEPOLIA --private-key $$REACTIVE_PRIVATE_KEY

e2e-testnet: ## 05: issuer price +MOVE_BPS (default 200) + mint on Sepolia → expect Lasna react + Base Sepolia callback
	$(ENV) cd $(C) && forge script script/05_TriggerIssuerMint.s.sol --rpc-url $$RPC_ETH_SEPOLIA --broadcast $(ORIGIN_FLAGS)

record: ## start recorder, all chains (Phase 12)
	@echo "record not implemented yet (Phase 12). See TODO.md." && exit 1

report: ## generate report JSON/CSV (Phase 12)
	@echo "report not implemented yet (Phase 12). See TODO.md." && exit 1

app: ## run dashboard dev server (app/, Vite) → http://localhost:5173
	cd app && pnpm install && pnpm dev

app-build: ## production build of the dashboard → app/dist (static)
	cd app && pnpm install && pnpm build
