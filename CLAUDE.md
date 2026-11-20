# NightShift — Claude Code instructions

Curated liquidity for tokenized stocks while Wall Street sleeps. Uniswap v4 hook + Reactive Network (Omni). UHI11 Hookathon, theme Active Management & Curated Liquidity. Deadline 3 Dec 2026 11:59 pm PST.

## Always-on context (Kiro steering is the source of truth)

@.kiro/steering/product.md
@.kiro/steering/tech.md
@.kiro/steering/structure.md
@.kiro/steering/glossary.md

## Scoped context

Loaded automatically through `.claude/rules/` when you touch matching files:
hook → uniswap-v4-hook · reactive/controller → reactive · vault/registry → vault-curation · tests → testing · any src → security, solidity · app → frontend · recorder → recorder.

## Read on demand

- Full spec: docs/SPEC.md (section numbers are stable — cite "SPEC §N" in commits/PRs). README.md = submission front page.
- Plan and status: TODO.md
- Decisions: .kiro/steering/decisions.md
- Deadlines, forms, pitch: .kiro/steering/hookathon.md

## Working rules

1. Follow TODO.md order; tick boxes only when acceptance criteria pass.
2. Before coding against a library, read its installed source (reactive-lib-omni, uniswap-hooks, v4-core/periphery).
3. Parameters live in contracts/config/*.json, never hard-coded in logic.
4. Every feature must pass the 4 project criteria + Reactive's 3 questions (product.md).
5. `make fmt && make test` before every commit; never commit .env or keys.
6. 🛑 Ask the user before: using private keys, any mainnet transaction, spending real funds, contacting anyone.
7. When reality contradicts README/steering: fix the file + add an ADR.
8. Prefer the smallest change that makes a test pass; no proxies; no vault swaps.

## Engineering discipline

- **Think before coding:** state assumptions; if multiple interpretations exist, surface them; if a simpler approach exists, say so. When unclear, stop and ask.
- **Simplicity first:** minimum code that solves the problem; no speculative features, abstractions, or error handling for impossible cases.
- **Surgical changes:** touch only what the task needs; match existing style; don't refactor what isn't broken; remove only orphans your change created.
- **Goal-driven:** turn each task into a verifiable check (write the test, then make it pass); every bug fix gets a regression test.

## Commands

make install · make build · make test · make test-scenarios · make deploy-testnet · make e2e-testnet · make record · make report · make app
