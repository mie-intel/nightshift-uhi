---
inclusion: fileMatch
fileMatchPattern: ["contracts/test/**"]
---

# Testing strategy (README §21)

## Rules
- TDD: write the failing test first; make it pass; keep it. **Every bug fix gets a regression test.**
- Naming: `Contract.t.sol`; scenarios `Scenario_SN_Name.t.sol`. `make fmt && make test` before every commit.
- Fuzz runs 256, invariant runs 64 (foundry.toml). Libraries coverage ≥ 90% lines (Phase 3 done criterion).

## Unit + fuzz (§21.1)
- `NyseCalendar`: every 2026–2027 holiday, early close, DST boundaries, weekends; fuzz `regimeAt` vs a reference table built in-test. Thanksgiving 26 Nov 2026 closed; 27 Nov 2026 early close 18:00 UTC.
- `PriceMath`: ratio↔tick round trip within 1 tick; decimals; inversion.
- `WitnessMath`: weighted median vs brute force (fuzz); EWMA bounds; clamp.
- `RiskMath`: ratchet monotonicity (fuzz).
- `FeeMath`: direction table; caps; splitting never cheaper (fuzz).
- Hook: permissions, dynamic-fee requirement, fees per regime, move caps, stale fallback, `curatedOnly`.
- Controller: auth (wrong sender, wrong identity, stale seq), try/catch per vault.
- Vault: deposit/withdraw pro-rata math, rebalance geometry, snapshot/reconcile math, HWM, mandate timelock.
- Reactive: decode each source kind from crafted `LogRecord`s, quorum rules, debounce, open window, timeouts.

## Local E2E: `ReactiveHarness` (§21.2) — doubles as documentation
Reactive can't run locally, so simulate:
1. `vm.etch(0x8888…8888, MockSystemContract)` — records `subscribe`, queues `requestCallbackV_1_0` configs.
2. Deploy reactive + destination contracts in one test (single chain, virtual chain IDs in source configs).
3. Harness turns origin events into `LogRecord`s, calls `react()` as SYSTEM.
4. Harness relays queued callbacks: overwrite first 32-byte arg with reactive identity, call Controller under `vm.prank(callbackProxy)`.
5. `vm.warp` to drive Cron ticks.
Integration test: close → witness move → anchor → (vault) → reopen → reconcile.

## Scenarios S1–S8 (§21.3) — each vs three pools: static / Gapguard-style / NightShift, identical liquidity & flows
| ID | Scenario | Expected NightShift |
| --- | --- | --- |
| S1 | Normal quiet weekend | Low fees, depth intact, small reconcile alpha |
| S2 | News weekend: issuer+siblings +4% Sat | Anchor follows in minutes; repair served; vaults at fair price; LP PnL ≫ static |
| S3 | HIMS-style one-way local buying, witnesses flat | Away fees + caps; risk ratchets; LP income ≫ static; premium contained |
| S4 | Thanksgiving + Black Friday early close + weekend | Correct regimes (closed Thu, open 14:30–18:00 UTC Fri, closed weekend) |
| S5 | Witness outage (no quorum) | Anchor frozen, staleness risk ↑, then max protection |
| S6 | Manipulate one sibling pool | Median/caps ignore it; effect < `maxJumpTicks` |
| S7 | Corporate action 10:1 split | Halt, rescale, recenter, resume |
| S8 | Two epochs: positive then negative alpha | Perf fee only above HWM |

## Metrics (per pool → `docs/recordings/scenarios.csv` + JSON via `make test-scenarios`)
Swaps filled, reverts, LP PnL vs HODL (quote), fees earned, avg trader cost, |pool price − reopen price| at open, depth within ±2% over time.

## Invariants (§15.2)
1. Hook state only via Controller; Controller only via authenticated callbacks/fallbacks. 2. `fee ≤ maxFeeClosed ≤ MAX_FEE`. 3. CLOSED → `riskBps` non-decreasing. 4. Anchor updated only with quorum. 5. `Σ withdrawable ≤ assets held`; no curator fund transfer. 6. Perf fee only when `cumAlpha > hwm`; `perfFeeBps ≤ 2000`. 7. `seq` strictly increasing per pool.
