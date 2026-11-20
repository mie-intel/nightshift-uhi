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
- **Decision:** Destination = Unichain Sepolia; origins = Ethereum Sepolia (MockIssuer + sibling A) + Base Sepolia (sibling B); reactive = Lasna. **Superseded by ADR-015 (destination = Base Sepolia).**
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

## ADR-014 Phase 4 walking-skeleton build decisions
- **Date:** 2026-11-20 · **Status:** Accepted
- **Context:** Building hook/controller/reactive v0 against the installed libraries surfaced compiler and wiring constraints.
- **Decision:**
  1. `NightShiftController` uses `pragma ^0.8.29` (reactive-lib-omni `AbstractCallback` requires it); other destination contracts stay `^0.8.26`.
  2. v4-core `PoolManager.sol` pins `pragma 0.8.26` exactly, so no file can import both it and reactive-lib. Tests deploy PoolManager from its artifact (`deployCode`); `test/utils/V4Artifacts.sol` (0.8.26) only forces the artifact build. The reactive build skips that file (`REACTIVE_SKIP` in Makefile). `foundry.toml` fs_permissions now include read `./out`.
  3. Deploy order breaks the address cycle: hook (CREATE2, mined) → reactive (Lasna) → controller pinned to (callback proxy, reactive, hook) → `hook.initController` (one-shot, by an explicit `owner` because CREATE2 makes the factory `msg.sender`) → `reactive.setController` + `subscribe()` (owner calls after deploy, not in the constructor).
  4. `NightShiftReactive` v0 = one issuer witness, no quorum; Phase 6 replaces it with the Witness Quorum. Hook v0 already runs the full FeeMath path (direction, fees, caps, stale fallback); `curatedOnly`/registry and local-divergence `riskUsed` land in Phase 5/7.
  5. Hook adds `initialized` to `PoolState` so callbacks for unknown pools revert (`UnknownPool`); `seq` is shared across `setState`/`setRegime` per pool (invariant 7).
  6. Chain addresses, demo prices and funding amounts live in `config/testnet.json` (`chains`, `demo`, `funding`); deploy outputs in `deployments/testnet.json`.
- **Consequences:** Scripts 00–05 fork-simulated OK against Sepolia + Unichain Sepolia (hook mined, pool initialized, liquidity seeded). Lasna steps (02/04) untested until the real deploy; `LASNA_FLAGS` lets us add e.g. `--legacy` without code changes.

## ADR-015 Destination chain = Base Sepolia (supersedes ADR-005 destination)
- **Date:** 2026-11-20 · **Status:** Accepted (user decision)
- **Context:** Unichain Sepolia ETH is hard to obtain; Base Sepolia ETH is easy, has 2 s blocks, a Reactive callback proxy (`0x476F…3585`), a v4 PoolManager (`0x05E7…3408`), the CREATE2 deployer, and an lREACT faucet (`0x2afa…5967`, 1 ETH → 100 lREACT) on the same chain. All four addresses verified on-chain (code present, chainId 84532).
- **Decision:** Destination = Base Sepolia. Origin = Ethereum Sepolia (MockIssuer + sibling pool A). Sibling pool B = plain v4 pool on Base Sepolia (separate market; a different chain from the issuer, so quorum still spans 2 chains). Reactive = Lasna. Config uses a chain-agnostic `chains.destination` block; deployments use a `destination` section, so a future move is config-only.
- **Consequences:** Wallet needs only Sepolia ETH (~0.05) + Base Sepolia ETH (~0.25). `make fund-reactive` uses the Base Sepolia faucet. Script 01 fork-simulated OK on Base Sepolia. The cross-chain story is intact: the issuer anchor lives on Ethereum Sepolia and is invisible to the Base Sepolia pool without Reactive.

## ADR-016 Frontend now, as a light Vite SPA (supersedes ADR-013's "frontend only if time")
- **Date:** 2026-11-20 · **Status:** Accepted (user decision)
- **Context:** User wants a simple dashboard that works and is very easy to operate, prioritising performance and small size. All data is on-chain and read client-side; no server rendering is needed.
- **Decision:** `app/` = Vite + React + TS + wagmi/viem + Tailwind v4, single page, injected wallet only, hand-rolled SVG instead of Recharts, system fonts. Warm light-brown palette with WCAG AA contrast; few eyebrow labels. Addresses from `deployments/testnet.json`.
- **Consequences:** Static deploy anywhere. Rubric impact: easier for judges (Functionality/Presentation) at ~1–2 days cost; contracts work (Phase 5/6) continues in parallel. A small public demo-token faucet contract is needed so judges can swap.

## ADR-017 Phase 5/6 build decisions (full hook, controller, reactive)
- **Date:** 2026-11-20 · **Status:** Accepted (supersedes ADR-007 Cron100)
- **Context:** Implementing the Witness Quorum, Cron regime and fallbacks against real Lasna costs and callback delivery semantics.
- **Decision:**
  1. **Cron1000 (~17 min), not Cron100.** One `react()` costs ~0.014 lREACT at 100 gwei; Cron100 (~720 ticks/day) ≈ 10 lREACT/day, Cron1000 ≈ 1 lREACT/day. Topic comes from `config.cron.topic0` (reactive constructor). Regime transitions may lag up to ~17 min; the destination `syncRegime` fallback covers it. Reactive gets an owner `withdraw` so funds aren't stranded on redeploy.
  2. **Two seq channels on the hook** (`lastSeq` anchor, `lastRegimeSeq` regime/reconcile). Reactive keeps one monotonic counter; callbacks are separate transactions and may land out of order, so a shared channel could drop a regime change as stale. Invariant 7 holds per channel.
  3. **Fallbacks don't consume seq:** `hook.forceRegime` (onlyController) used by `syncRegime` (calendar) and `forceReconcile` (timeout).
  4. **`onReconcile` carries `seq`** (README §13.1 signature extended) and sets the regime to OPEN; reconcile resets the risk ratchet, then OPEN risk follows the raw score. Vault scoring attaches here in Phase 8.
  5. **Open price:** the anchor computed during the open window with issuer weight ×`issuerOpenBoost` (instead of a separate window buffer).
  6. **Decoders built:** ISSUER_MINT/REDEEM (quote/shares), V4_SWAP + SELF (post-swap tick). V3_SWAP/ORACLE/ISSUER_ACTION not wired. `minNotional` applies to issuer events only.
  7. **Influence cap is per print:** a +4% move reaches the anchor over a few prints (first print capped at `maxJumpTicks`), then the hook updates only when the move ≥ `minAnchorDeltaTicks`.
  8. **Hook local-divergence floor:** `riskUsed = max(stored, weightDivergence·min(1, |d|/divergenceFull))` (README §8.3); hook constructor takes `RiskParams`.
  9. **Topology:** issuer (Ethereum Sepolia, w5) + sibling v4 pool B (Base Sepolia, plain pool, same pair, w2) + SELF → quorum spans 2 chains. Sibling A on Sepolia dropped (cost/time).
  10. **PriceMath precision fix:** ratios < 2^64 use `sqrt(q·2^192/b)`; fuzz found tick errors for tiny ratios via the X128 path (regression test added).
- **Consequences:** 140 tests green incl. a full local weekend (`test/integration/WeekendLoop.t.sol`). `react()` at 16 sources ≈ 116k gas. Redeploy of destination + reactive required (new hook/pool/controller/faucet); MockIssuer on Sepolia reused.
