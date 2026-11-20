---
inclusion: manual
---

# Decision log (ADRs)

> Template per entry: `## ADR-NNN Title` · **Date** · **Status** · **Context** · **Decision** · **Consequences**.
> Add an ADR whenever reality contradicts README/steering, or a non-obvious choice is made.

## ADR-001 Reactive Omni API is the target
- **Date:** 2026-11-18 · **Status:** Accepted
- **Context:** Reactive offers legacy RVM and the newer Omni API. README specifies Omni (`SYSTEM` callbacks, no RVM, no `Callback` event).
- **Decision:** Build against Reactive Omni: `AbstractReactive`/`AbstractCallback`, `SYSTEM 0x8888…8888`, `requestCallbackV_1_0`, first-arg identity authentication.
- **Consequences:** Exact API verified in Gate 0.3 before coding. No RVM assumptions anywhere.

## ADR-002 All prices in destination tick space
- **Date:** 2026-11-18 · **Status:** Accepted
- **Context:** Witnesses come from many chains/decimals/quote units. Comparisons and medians must be unit-free and cheap.
- **Decision:** Normalize every observation into the destination pool's tick space (1 tick ≈ 1 bp). `offsetTicks` encodes decimals/quote/multiplier, computed off-chain + unit-tested.
- **Consequences:** Median/dispersion/distance are plain tick arithmetic. Offset mistakes are the main normalization risk → test `ComputeOffsets`.

## ADR-003 Vault flows are in-kind pro-rata; vault never swaps
- **Date:** 2026-11-18 · **Status:** Accepted
- **Context:** Pricing deposits/withdrawals with a (possibly stale) anchor invites NAV games.
- **Decision:** Deposits/withdrawals in-kind pro-rata at current composition; vault never swaps; imbalance tolerated in wide/idle.
- **Consequences:** No price needed for flows → stale-NAV games impossible. Inventory can be imbalanced; acceptable.

## ADR-004 Fee semantics: toward served + gap capture, away steep + capped
- **Date:** 2026-11-18 · **Status:** Accepted
- **Context:** Idea form said "toward stays cheap". Refined: repair flow should be served (not reverted) while LPs capture part of the gap; destabilizing flow pays and is capped.
- **Decision:** Toward = served, `captureShare` (30%) of gap to LPs. Away = steep risk-scaled fee at midpoint of a full step (split never cheaper) + move cap.
- **Consequences:** Replaces the simpler "toward cheap" wording. Tuned via scenarios (ADR to follow with final params in Phase 10).

## ADR-005 Testnet topology
- **Date:** 2026-11-18 · **Status:** Accepted
- **Context:** Reactive supports Base Sepolia, Ethereum Sepolia, Unichain Sepolia, Lasna as testnets; Robinhood Chain & BSC are mainnet-only.
- **Decision:** Destination = Unichain Sepolia; origins = Ethereum Sepolia (MockIssuer + sibling A) + Base Sepolia (sibling B); reactive = Lasna.
- **Consequences:** Primary build/demo target. Mainnet (Robinhood Chain) is a stretch showcase only.

## ADR-006 Destination calendar fallback + anchor staleness (defense in depth)
- **Date:** 2026-11-18 · **Status:** Accepted
- **Context:** Reactive could be late or down; the pool must not trust stale state.
- **Decision:** Compile `NyseCalendar` into both reactive and controller; permissionless `syncRegime`/`forceReconcile`; hook stale-anchor fallback degrades to maximal (Gapguard-like) protection.
- **Consequences:** System degrades safely without Reactive, at the cost of duplicated calendar logic (kept identical).

## ADR-007 Cron100 for regime/heartbeat timing
- **Date:** 2026-11-18 · **Status:** Accepted (Gate 0.3)
- **Context:** Omni Cron lives on legacy sys contract `0x00..fffFfF` with topics Cron1/10/100/1000/10000 (~1s/10s/2min/17min/3h on ~1s blocks). Cron bills on every tick regardless of `react()` work. README guessed "~100 blocks ≈ 100 s".
- **Decision:** Subscribe to **Cron100** (topic0 `0xb49937fb…1503c70`, ~2 min) for regime-transition detection, heartbeat, open-window close and reconcile timeout. Evaluate all time-driven logic off `block.timestamp` in `react()`.
- **Consequences:** ~2 min granularity is fine for NYSE transitions (14:30/18:00/21:00 UTC). ~720 billed ticks/day — acceptable; if cost bites, switch to Cron1000 (~17 min) and accept coarser transition timing.

## ADR-008 Callback auth uses BOTH lib modifiers
- **Date:** 2026-11-18 · **Status:** Accepted (Gate 0.3/E)
- **Context:** `AbstractCallback.onlyCallbackSender` only checks the injected first-arg == `_CALLBACK_SENDER`; it does NOT check `msg.sender`. `_CALLBACK_SENDER` is public, so a direct caller could spoof it. Docs say "use both, always."
- **Decision:** Every Controller callback carries `onlyServiceProvider onlyCallbackSender(reactive_)`: proxy-is-caller AND injected identity. Constructor `AbstractCallback(callbackProxy, expectedReactive)`.
- **Consequences:** Matches README §15 threat "forged callbacks". A test asserts a direct call (correct first arg, wrong msg.sender) reverts `NotAuthorized`.

## ADR-009 Single `onAnchor` loops vaults on the destination; `react()` ≤ 900k
- **Date:** 2026-11-18 · **Status:** Accepted (Gate 0.6)
- **Context:** Reactive caps a reactive transaction (`react()`) at 900 000 gas. Callback min 100k; destination callback gas bounded by the destination block, not the 900k cap. README proposed `onAnchor` looping all vaults.
- **Decision:** Keep witness quorum/risk math inside `react()` under 900k (lean median/EWMA, `MAX_SOURCES=16`); do the per-vault loop in the **destination** `onAnchor` callback with `try/catch`, `gasLimit` 2.5M (8-vault cap). 
- **Consequences:** `react()` gas is a hard design budget — profile it in Phase 6. Fallback: if 8 vaults exceed a safe destination gas, split into per-vault callbacks.

## ADR-010 Ondo issuer events are a bonus; StablePair + sibling Swaps are primary
- **Date:** 2026-11-18 · **Status:** Accepted (Gate 0.1, provisional)
- **Context:** Ondo 24/7 mint/redeem is live on Ethereum/BNB but uses off-chain signed attestations; no verified on-chain event emitting share AND quote amounts was found in public sources.
- **Decision:** For the mainnet showcase (Phase 11.M, stretch), use StablePair + sibling v4 `Swap` events as primary witnesses. Wire a real Ondo issuer event only after confirming its ABI on Etherscan. Testnet uses `MockIssuer` regardless.
- **Consequences:** No build dependency on an unverified ABI. Revisit before 11.M: find GM token/manager contracts, read logs, compute `offsetTicks`. Revise this ADR if a usable event is confirmed.

## ADR-011 Testnet-only scope; Ondo = MockIssuer; mainnet showcase out of scope
- **Date:** 2026-11-18 · **Status:** Accepted (supersedes ADR-010 for our scope)
- **Context:** Real Ondo mint/redeem is mainnet-only (Ethereum/BNB). Reactive forbids mixing mainnet and testnet, and our reactive contract runs on Lasna (testnet), so a Lasna reactive contract cannot witness real Ondo events. User chose to focus on testnet only.
- **Decision:** Build, demo and submit entirely on the testnet topology (ADR-005). The issuer witness is always `MockIssuer` (`Minted(address,uint256,uint256)`) on Ethereum Sepolia; price moves driven by the flow bot. **Phase 11.M (mainnet showcase) is out of scope.** G0.1 and G0.7 are N/A (both were mainnet-showcase concerns).
- **Consequences:** Reactive is unchanged and still core — it still witnesses multiple testnet origins (Eth Sepolia + Base Sepolia), computes on Lasna, and callbacks to Unichain Sepolia between trades; Gate 1 is still a real Lasna→Unichain-Sepolia callback. Only the issuer *data source* is mocked (unavoidable on testnet), not Reactive. No mainnet keys/funds, no Ondo-ABI work. `mainnet.json` kept as a stub only.

## ADR-012 Phase 3 library clarifications (fee units, ratchet scope, rounding)
- **Date:** 2026-11-20 · **Status:** Accepted
- **Context:** Writing `FeeMath`/`RiskMath` test-first exposed two spec gaps. (1) README §9.2 wrote the toward fee as `captureShare · |d| · 100`; with `captureShare` in bps that is 10 000× too large (200-tick gap → 6e7 pips). (2) §8.2 defined the ratchet only for `CLOSED`/`OPEN`, leaving `REOPEN_PENDING`/`HALTED` undefined.
- **Decision:** (1) Toward fee while CLOSED = `baseClosed + captureShare · absD / 100` pips (30% of a 200 bp gap = 6 000 pips = 60 bp, matching the README's own example). (2) Every non-OPEN regime ratchets (`max(prev, raw)`); only reconciliation resets risk to 0. (3) `PriceMath.tickFromRatio` floors like `TickMath`; exactly on a tick boundary it may return one tick lower (spec tolerance ±1). (4) Neutral (deadband) swaps pay the toward fee, so they are bound by the tighter `overshootCap`, not `maxAwayMove` — otherwise a neutral swap would be a cheap away swap. (5) Move caps and overshoot apply only outside OPEN.
- **Consequences:** README §9.2 and §8.2 updated. Tests in `test/unit/{FeeMath,RiskMath,PriceMath}.t.sol` pin the behaviour.

## ADR-013 MVP scope aligned to the Atrium rubric; tests-first
- **Date:** 2026-11-20 · **Status:** Accepted
- **Context:** Atrium rubric (guideline.pdf): Original Idea 30%, Unique Execution 25%, Impact 20%, Functionality 15%, Presentation 10%. Testnet deployment and frontend not mandatory; tests OR frontend required. 13 days left with no contract code.
- **Decision:** Tests-first, no dashboard unless the core is done by ~29 Nov. Must-have: Gate 1, hook, reactive (≥2 witness chains, quorum, Cron regime), one vault (recenter + reconcile vs HODL + HWM), scenarios S2/S3/S5/S6 vs static pool, one recorded live loop. Cut to slides: corporate actions (S7), `migrate`, mandate timelocks, multiple presets, leaderboard UI. See hookathon.md.
- **Consequences:** TODO phases 9 (corporate actions), 13 (dashboard) and parts of 7/10/12 become stretch. Submission README must list only built integrations.
