---
inclusion: fileMatch
fileMatchPattern: ["contracts/src/hook/**", "contracts/src/libraries/FeeMath.sol"]
---

# NightShiftHook spec (SPEC §9, §13.1)

## Permissions & deployment
- Hooks used: `afterInitialize`, `beforeAddLiquidity`, `beforeSwap`, `afterSwap`. **No return-delta flags.**
- Address mined with `HookMiner` for exactly those flags; deployed via CREATE2 deployer `0x4e59b44847b379578588920cA78FbF26c0B4956C`.
- Inherit `BaseHook` (OZ uniswap-hooks or v4-periphery — Gate 0.5; use whichever compiles cleanly, record the import path).

## Dynamic fee mechanics
- Pool created with `fee = LPFeeLibrary.DYNAMIC_FEE_FLAG`. `beforeSwap` returns `fee | LPFeeLibrary.OVERRIDE_FEE_FLAG`. Units = pips (1e6 = 100%).
- All surcharge accrues to the liquidity that fills the swap — no lump sum for JIT to capture.

## Per-swap flow
- `afterInitialize`: revert unless `key.fee == DYNAMIC_FEE_FLAG` (`NotDynamicFee`); load `PoolConfig` from registry.
- `beforeAddLiquidity`: if `curatedOnly`, require `sender` is a registered vault (`NotCuratedVault`).
- `beforeSwap`: compute fee via `FeeMath` (§9.2), **stash `tickBefore` + `away` in transient storage**, return override fee.
- `afterSwap`: enforce move caps (§9.3), emit `SwapObserved(poolId, tickBefore, tickAfter, fee, away)`.

## Direction (§9.1)
`d = currentTick − anchorTick` before swap. `|d| ≤ deadbandTicks` (5) → neutral (treated as toward). `toward` ⇔ (`zeroForOne` && `d>0`) or (`!zeroForOne` && `d<0`); else `away`.

## Fee schedule (§9.2) — toward is served, away is steep
- Toward = repair flow: served, recapture `captureShare` (30%) of the gap for LPs.
- Away = pushing off fair value: steep, risk-scaled, priced at midpoint of a full allowed step so **splitting a swap is never cheaper** (Gapguard idea, MIT credited).
- Caps: `maxFeeClosed` (50 000 = 5%); hard `MAX_FEE = 100 000` (10%) checked at construction. `riskUsed = max(storedRisk, localDivergenceComponent)` so a late callback can't make fees too cheap.

## Move caps (§9.3, in afterSwap)
- away while CLOSED/REOPEN_PENDING: `|tickAfter − tickBefore| ≤ maxAwayMove · (1 − riskUsed/20 000)` else `AwayMoveTooLarge()` (default 100 ticks).
- toward may overshoot anchor by ≤ `overshootCap` (20) else `Overshoot()`. Large toward swaps served in full up to the anchor — the core difference from a blanket move cap.

## Stale-anchor fallback (§9.4)
If `now − anchorUpdatedAt > anchorMaxAge(regime)` (30 min open / 6 h closed) or no anchor ever set → every swap treated as `away`, `riskUsed = 10 000`; emit `AnchorStale(poolId)` once per stale period. Defense in depth = degrade to Gapguard-like max protection.

## State & externals
- `PoolState{int24 anchorTick; uint40 anchorUpdatedAt; uint16 riskBps; uint16 dispersionTicks; Regime regime; uint64 lastSeq; bool curatedOnly}`.
- `setState(PoolId, int24 anchorTick, uint16 riskBps, uint16 dispersion, uint64 seq)` onlyController, require `seq > lastSeq`.
- `setRegime(PoolId, Regime, uint64 seq)`, `applyCorporateAction(PoolId, int24 tickShift, uint64 seq)` onlyController.
- `quoteFee(PoolKey, bool zeroForOne) view returns (uint24 fee, bool away)` — routers/quoters/dashboard.
- Errors: `NotController, StaleSeq, MarketHalted, AwayMoveTooLarge, Overshoot, NotDynamicFee, NotCuratedVault`.
- Params per pool from `PoolConfig`, set at `afterInitialize`, changeable only by pool admin via 24 h timelock.

## FeeMath library
Pure functions: direction, fee schedule per regime, move caps. Fuzz: splitting a swap is never cheaper; fee ≤ caps always. HALTED → revert `MarketHalted()`.
