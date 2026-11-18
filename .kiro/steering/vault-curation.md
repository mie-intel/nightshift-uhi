---
inclusion: fileMatch
fileMatchPattern: ["contracts/src/vault/**", "contracts/src/registry/**"]
---

# Vaults, curation, registry (README §10, §11, §12)

## Roles (§10.1)
- **Curator**: deploy vault via factory, queue timelocked mandate changes, earn perf fees. CANNOT move funds, pick arbitrary rebalance ticks, or change fees.
- **Depositor**: in-kind deposit/withdraw, migrate between vaults of the same pool.
- **Controller** (Reactive-fed): push anchor/regime/risk; call `rebalance`/`snapshotClose`/`reconcile`. Nothing else.
- **Pool admin** (multisig): register pools, set `PoolConfig` (timelocked), emergency pause. Never touches vault funds.

## Mandate (§10.2)
```solidity
struct RegimeMandate { uint16 followBps; uint24 coreHalfWidth; uint24 wideHalfWidth;
  uint16 coreShareBps; uint16 riskWidenBps; uint24 recenterThreshold; uint16 exitRiskBps; }
struct Mandate { RegimeMandate open; RegimeMandate closed; RegimeMandate reopen; uint16 perfFeeBps; } // ≤ MAX_PERF_FEE 2000
```
`center = poolTick + followBps·(anchor − poolTick)/10 000`. `width·(1 + riskWidenBps·risk/1e8)`. Presets: Conservative / Balanced / Aggressive (in `script/` + dashboard). `queueMandate` → `applyMandate()` after `mandateTimelock` (24h); never mid-CLOSED (applies at next OPEN).

## Vault mechanics (§10.3)
- One vault = one pool, one curator. ERC-20 shares (OZ `ERC20`), `ReentrancyGuard`.
- Holds idle token0/token1 + up to two positions (`core`, `wide`) with distinct `salt`s, via `poolManager.unlock()` + `unlockCallback` + `modifyLiquidity`, settling with `CurrencySettler`.
- **Deposits/withdrawals in-kind pro-rata** (LP-token style): shares at current composition ratio, refund excess; withdraw returns pro-rata liquidity + idle. **No price needed for flows** → no stale-NAV games.
- **Vault never swaps.** Imbalance tolerated (sits in wide/idle).
- `rebalance(anchorTick, riskBps, regime)` (onlyController): pick mandate; if `risk ≥ exitRiskBps` remove core keep wide; else compute center+widths (risk-widened, round to `tickSpacing`); if move < `recenterThreshold` no-op (`RebalanceSkipped`); else remove+re-add with available balances (single-sided fine).
- Protects LPs: liquidity moved off stale prices onto witnessed fair price; repair flow trades near fair value.

## Reconciliation & perf fees (§11)
- Epoch = one closed period; `epochId++` on each CLOSED entry.
- `snapshotClose(epochId)`: record per-share composition `(a0,a1)` at current sqrtPriceX96 + idle / totalSupply (unaffected by in-kind flows).
- `reconcile(openTick, epochId)`: `hodlPerShare = a0·P_open + a1`; `navPerShare = positions@openTick + idle / supply`; `alphaPerShare = nav − hodl`; `cumAlpha += alpha`; if `cumAlpha > hwm` mint curator shares worth `perfFeeBps·(cumAlpha − hwm)/10 000 · supply` at nav, set `hwm = cumAlpha`. Emit `EpochReconciled`, `registry.record(...)`. Valuation uses **witnessed open tick**, never pool spot.

## Corporate actions (§12)
`ISSUER_ACTION` → `onCorporateAction(ratioNum, ratioDen, effectiveAt)` → Controller HALTED → hook rescales anchor (`anchorTick += tickOf(ratio)`), source offsets updated on Reactive → force recenter all vaults → HALTED lifts after next valid anchor or `maxHaltDuration` (30 min).

## Registry, leaderboard, migration (§10.4)
- `CuratorRegistry`: profiles, vault list per pool (`MAX_VAULTS_PER_POOL = 8`), per-epoch results, cumulative alpha/share, epochs played, best/worst.
- `registerPool`(admin), `queuePoolConfig`/`applyPoolConfig` (timelocked), `registerVault` (factory only), `vaultsOf`, `isVault`, `record` (vault only), leaderboard views.
- `migrate(fromVault, toVault, shares, amount0Min, amount1Min)`: in-kind withdraw → deposit in one tx, refund leftovers.
- `VaultFactory.create(PoolKey, Mandate, name, symbol)` → registers in registry. Curator bond out of scope v1 (future work).
