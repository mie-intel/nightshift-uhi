---
inclusion: fileMatch
fileMatchPattern: ["contracts/src/reactive/**", "contracts/src/controller/**", "contracts/src/libraries/WitnessMath.sol", "contracts/src/libraries/RiskMath.sol", "contracts/src/libraries/PriceMath.sol"]
---

# Reactive + Controller spec (SPEC §7, §8, §13.2, §14, §18.1–18.2)

> API below **verified** against `reactive-lib-omni` source + docs (docs/verification.md G0.3). Re-read the installed source at Phase 2 pin time in case of version drift.

## The rule that defines success (SPEC §1.3)
A callback must **actually fire**: reactive tx on Lasna/mainnet **+** the destination callback tx, both visible in explorers. Gate 1 is the first milestone. Never mix Lasna and mainnet.

## Callback authentication (VERIFIED G0.3/E — use BOTH modifiers, always)
- Controller `is AbstractCallback`; constructor `AbstractCallback(callbackProxy_, expectedReactive_)` (both immutable).
- Each callback: `function onX(address reactive_, ...) external onlyServiceProvider onlyCallbackSender(reactive_)`. `onlyServiceProvider` = `msg.sender == callbackProxy`; `onlyCallbackSender` = injected first-arg `== _CALLBACK_SENDER`. Omitting `onlyServiceProvider` lets anyone call directly with a spoofed first arg — never omit it.

## Reactive contract (`NightShiftReactive`, ^0.8.29)
- `SYSTEM = ISystemContract(payable(0x8888…8888))`; `react(IReactive.LogRecord calldata log_) external onlySystem` (**calldata**). `REACTIVE_IGNORE = 0xa65f96fc…2313ad`.
- Subscriptions: one per witness source + destination pool `SELF` Swap + issuer action + **Cron100** (legacy sys `0x00..fffFfF`, topic0 `0xb49937fb…1503c70`, ~2 min; bills every tick). `subscribe(chainId, contract, topic0, topic1, topic2, topic3)` — **6 args**, unused topics = `REACTIVE_IGNORE`; no OR in a subscription.
- **`react()` must fit in 900 000 gas** (Reactive-tx cap): keep decode + EWMA + weighted median (`MAX_SOURCES=16`) + risk lean; no vault loop here. Fund via `SYSTEM.depositTo(this){value}`; expose `coverDebt()`; any debt blocks execution.
- `requestCallbackV_1_0(CallbackConfiguration_V_1_0{chainId, recipient: controller, gasLimit, payload})`, payload = `abi.encodeWithSelector(IController.onX.selector, address(0), ...)`.
- Admin (owner): `addSource`, `disableSource`, `setParams`, `setController`, `pause`. Funded with REACT (lREACT on Lasna); funding/charge/debt mechanism Gate 0.3.
- Gas (defaults, tune): onAnchor 2.5M, onRegime 1.5M, onReconcile 2.5M, onCorporateAction 2.5M. Max/cost Gate 0.6 (fallback: per-vault callbacks).

## Witness quorum (§7)
- Source kinds + weights: `ISSUER_MINT/REDEEM` 5, `V4_SWAP` 3 (StablePair)/2 (other), `V3_SWAP` 2, `ORACLE` 1, `SELF` 0 (never in anchor, used for divergence).
- Normalize to dest tick space: `destTick = (invert ? −srcTick : srcTick) + offsetTicks`. Issuer: ratio → sqrtPriceX96 → `TickMath.getTickAtSqrtPrice`. `offsetTicks` computed off-chain by `ComputeOffsets` + unit-tested.
- Per source: notional filter (`minNotional`), influence cap `clamp(x, anchor±maxJumpTicks=300)`, time-weighted EWMA `α = 1 − 2^(−Δt/halfLife=300s)`.
- Fresh if `now − lastSeen ≤ maxAge(regime)`; `w_eff = weight · (1 − age/maxAge)`.
- **Quorum** iff Σ w_eff ≥ `minQuorumWeight` (4) **and** fresh sources span ≥ `minDistinctChains` (2). Anchor = weighted median of `ewma_s` (insertion sort, `MAX_SOURCES=16`). Dispersion = weighted MAD. No quorum → anchor NOT updated, status DEGRADED, risk keeps rising.

## Debounce / when to callback (§7.6)
`onAnchor` iff quorum AND (`|anchor − lastSent| ≥ minAnchorDeltaTicks=10` OR risk bucket (500 bps) changed OR heartbeat 30 min) AND `now − lastCallbackAt ≥ minCallbackInterval=60s`. **Regime, reconcile, corporate-action bypass the debounce.** Every callback carries monotonically increasing `seq`.

## Risk (§8, RiskMath) — the ratchet
Components (→[0,1], weights sum 10 000): Time (H_full 64h, w3000), Dispersion (D_full 200t, w2500), Divergence (V_full 300t, w3000), Staleness (S_full 4h, w1500). CLOSED: `risk = max(risk, raw)` (monotonic). OPEN: `risk = raw`. Reconcile: `risk = 0`, `lastOpenAnchorAt = now`.

## Regime on Cron (§6.3)
`NightShiftReactive` evaluates `NyseCalendar` for `block.timestamp` each Cron tick; on transition requests `onRegime` (no debounce). REOPEN_PENDING → OPEN only via `onReconcile` (or `forceReconcile` after `reconcileTimeout`). Open window default 15 min, issuer weight ×2; timeout 60 min → degraded reconcile.

## Controller callbacks (all onlyReactive)
`onAnchor` → `hook.setState` → per-vault `try vault.rebalance` (fail → `VaultRebalanceFailed`, never revert). `onRegime` → `hook.setRegime`; CLOSED → start epoch + `vault.snapshotClose`. `onReconcile` → each `vault.reconcile` → `hook.setRegime(OPEN)`. `onCorporateAction` → halt/rescale/recenter. Permissionless fallbacks: `syncRegime(poolId)`, `forceReconcile(poolId)`.

## Events on Reactive (§14.4)
`WitnessObserved`, `QuorumComputed`, `CallbackRequested`.
