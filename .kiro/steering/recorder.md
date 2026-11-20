---
inclusion: fileMatch
fileMatchPattern: ["recorder/**"]
---

# Recorder & flow bot (`recorder/`) spec (SPEC §22.1–22.2)

## Recorder
- `viem` watchers per chain (origin, destination, Lasna/Reactive mainnet) for all events in SPEC §14; store block time, tx hash, chain ID.
- **Resumable** from last processed block; **idempotent** writes. Store: `better-sqlite3` or JSONL in `recorder/data/` (gitignored).
- Config comes from `deployments/{network}.json` — never hard-code addresses.
- `report` command output (JSON for dashboard): anchor vs pool tick per pool, risk, regime bands, per-epoch vault results, three-pool comparison metrics, callback latency (origin event → destination callback).

## Flow bot
- **Testnet:** scripted "market" — move MockIssuer price, trade sibling pools to simulate news, send a realistic toward/away mix to all three destination pools.
- **Mainnet showcase:** trades ONLY our demo pools; witnesses are real.
- **Honesty rule (pitch + UI must state):** destination flow is **scripted**; on mainnet the **anchor/witnesses are real**. Never imply scripted flow is organic.

## Commands
`make record` (start recorder, all chains) and `make report` (CSV/JSON + charts) must work against testnet deployments.
