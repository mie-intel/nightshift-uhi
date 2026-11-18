# Gate 0 verification (README §25)

Date: 2026-11-18. Method: read installed `reactive-lib-omni` + `OpenZeppelin/uniswap-hooks` source (shallow clones), Reactive dev docs (dev.reactive.network), web search. Each item: **Question · Evidence · Answer · Impact**.

Status legend: ✅ answered · ⚠️ partial / verify live · 🛑 user action.

---

## G0.3 — Reactive Omni lib API ✅ (was blocking)

**Question:** Exact Omni API: `AbstractReactive`, `onlySystem`, `LogRecord`, `subscribe` sig, `REACTIVE_IGNORE`, Cron topics/intervals, `AbstractCallback` constructor + modifiers, funding/charging + debt repayment.

**Evidence:** `reactive-lib-omni` (branch `master`, 8 source files) + docs pages `/subscriptions` (= Reactive Contracts page), `/callback-contracts`, `/economy`, `/reactive-mainnet`.

**Answer:**
- `SYSTEM = ISystemContract(payable(0x8888888888888888888888888888888888888888))` (constant in `AbstractReactive`).
- `REACTIVE_IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad`.
- Reactive entry: `function react(IReactive.LogRecord calldata log_) external` guarded by `onlySystem` (impl `_onlyServiceProvider`: `msg.sender == SYSTEM`). **Note: `calldata`, not `memory` as README said.**
- `LogRecord{uint256 chainId; address contractAddress; uint256 topic0; topic1; topic2; topic3; bytes data; uint256 blockNumber; opCode; blockHash; txHash; logIndex}`.
- `subscribe(uint256 chainId_, address contract_, uint256 topic0_, topic1_, topic2_, topic3_)` — **6 args, all four topics**; `chainId_=0` = all chains, `contract_=0` = all, topic `REACTIVE_IGNORE` = wildcard. `unsubscribe(...)` same shape.
- Callback request: `SYSTEM.requestCallbackV_1_0(CallbackConfiguration_V_1_0{uint256 chainId; address recipient; uint64 gasLimit; bytes payload})`. Also generic `requestCallback(CallbackVersion.V_1_0, abi.encode(config))`.
- A deprecated legacy `Callback(...)` event exists in `IReactive` but is **not** the Omni path — use `requestCallback*`. (README said "no Callback event"; correction: it exists but is legacy/deprecated.)
- **Cron:** legacy system contract `0x0000000000000000000000000000000000fffFfF` emits Cron events; subscribe via SYSTEM. Topics/intervals (~1 s blocks):

  | Event | Interval | topic0 |
  | --- | --- | --- |
  | Cron1 | ~1 s | `0xf02d6ea5c22a71cffe930a4523fcb4f129be6c804db50e4202fb4e0b07ccb514` |
  | Cron10 | ~10 s | `0x04463f7c1651e6b9774d7f85c85bb94654e3c46ca79b0c16fb16d4183307b687` |
  | Cron100 | ~2 min | `0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70` |
  | Cron1000 | ~17 min | `0xe20b31294d84c3661ddc8f423abb9c70310d0cf172aa2714ead78029b325e3f4` |
  | Cron10000 | ~3 h | `0xd214e1d84db704ed42d37f538ea9bf71e44ba28bc1cc088b2f5deca654677a56` |

  Subscribe e.g. `SYSTEM.subscribe(block.chainid, 0x..fffFfF, CRON100_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE)`. Event data = one `number` (block). **Cron bills every tick even if `react()` no-ops.**
- **Funding/debt** (`AbstractPayer`): `receive()` payable; `pay(uint256)` only callable by service provider (pulls); `_coverDebt()` pays `_SERVICE_PROVIDER.debt(this)`; errors `NotAuthorized/InsufficientFunds/TransferFailed`. Fund reactive via `SYSTEM.depositTo(reactiveAddr){value}` (settles debt first); fund callback contract via `callbackProxy.depositTo(controllerAddr){value}` in the destination **native token** (ETH/BNB, never REACT). Expose `function coverDebt() external { _coverDebt(); }`. **Any debt > 0 blocks execution** (`BlacklistContract`/`WhitelistContract` events).

**Impact:** Corrects README §13.2 (`memory`→`calldata`, Cron100 ≈ 2 min not ~100 s, Cron lives on `0x..fffFfF`, "no Callback event" wording). tech.md + reactive.md updated; see ADR-007, ADR-008.

---

## G0.5 — which `BaseHook` ✅

**Question:** OZ uniswap-hooks `BaseHook` or v4-periphery? Exact import paths.

**Evidence:** `OpenZeppelin/uniswap-hooks` v1.3.0 source.

**Answer:** Use OZ uniswap-hooks. `BaseHook` at `@openzeppelin/uniswap-hooks/src/base/BaseHook.sol` (pragma `^0.8.26`; constructor `(IPoolManager)`; `_validateHookAddress`; `onlyPoolManager`; internal `_beforeSwap/_afterSwap/_afterInitialize/_beforeAddLiquidity` overrides; `getHookPermissions`). **Extend `@openzeppelin/uniswap-hooks/src/fee/BaseOverrideFee.sol`** — it already: reverts non-dynamic-fee in `_afterInitialize` (gives `NotDynamicFee`), declares abstract `_getFee(...)`, and in `_beforeSwap` returns `fee | LPFeeLibrary.OVERRIDE_FEE_FLAG` after `fee.validate()`. Its `getHookPermissions` sets only `afterInitialize`+`beforeSwap`.

**Impact:** `NightShiftHook is BaseOverrideFee`. Override `getHookPermissions` to also enable `beforeAddLiquidity` (curatedOnly) + `afterSwap` (move caps); implement `_getFee`, `_afterSwap`, `_beforeAddLiquidity`. Import roots: `@uniswap/v4-core/src/...`, `@openzeppelin/uniswap-hooks/src/...`. Fee units = hundredths of a bip (pips), confirmed.

---

## G0.4 — EVM version for Reactive deploys ✅ (verify live)

**Question:** Supported EVM version on Reactive Omni for 0.8.29.

**Evidence:** Docs examples use `pragma solidity ^0.8.29;`; `forge create` example has no `evm_version` flag; "Reactive lands on HyperEVM" post = Cancun-era EVM; roadmap targets 0.8.29, earlier versions work.

**Answer:** Compile `NightShiftReactive` with `^0.8.29`, `evm_version = "cancun"` (matches destination; Cancun-era confirmed for the network family). No special flag required by docs.

**Impact:** `[profile.reactive]` → `evm_version = "cancun"`, `solc 0.8.29`. **Confirm by a real Lasna deploy in Phase 4** (Gate 1) before trusting. Fallback if it rejects transient storage: downgrade reactive profile to `paris`/`shanghai` and avoid tstore in `react()`.

---

## G0.6 — callback gas limit & cost; onAnchor topology ✅ (ADR-009)

**Question:** Max callback gas + per-callback cost; single `onAnchor` loop vs per-vault callbacks.

**Evidence:** `/economy`: min callback gas **100 000** (below = ignored); **max callback gas NOT published**; reactive-transaction max = **900 000** (this caps `react()` on the Reactive side, NOT the destination callback). Fee `fee = p_base · C · (g_used + K)`, reactive defaults `C=1000/1000=1`, `K=100 000` surcharge, `_maxChargeGas=50 000`; callback proxies have no defaults (vary by destination chain). Failed callbacks still charged; proxy withholds `_extraGas`+`_maxChargeGas` then forwards remainder (`InsufficientGas` if too little).

**Answer:**
- **`react()` must fit in 900 000 gas** (Reactive-side cap). Keep witness math lean: `MAX_SOURCES=16`, insertion-sort median, fixed-point EWMA — profile it. Heavy per-vault work does NOT belong in `react()`.
- The **vault loop belongs in the destination `onAnchor` callback** (normal destination-chain gas, min 100k, bounded by destination block limit — not the 900k reactive cap). Keep README default `gasLimit = 2 500 000` for `onAnchor` (8-vault cap, try/catch), tune from measurement in Phase 6/11.
- Decision: **single `onAnchor` that loops vaults with `try/catch`** (ADR-009). Fallback to per-vault callbacks only if destination gas for 8 vaults proves too high.

**Impact:** Confirms the Controller-loops-vaults design; adds a hard `react()` ≤ 900k budget constraint. tech.md updated.

---

## G0.1 — Ondo 24/7 mint/redeem events ✅ N/A (testnet-only, ADR-011)

> Scope decision (ADR-011): testnet-only; issuer witness is always `MockIssuer`. Real Ondo is mainnet and cannot be witnessed from a Lasna reactive contract. The analysis below is retained for reference / any future mainnet work.

**Question:** Do Ondo's 24/7 mint/redeem contracts on Ethereum/BNB emit events with share **and** quote amounts? Which contracts/events?

**Evidence:** Ondo launched 24/7 mint/redeem on Ethereum + BNB Chain (tokens SPYon, QQQon, NVDAon, TSLAon, GOOGLon, CRCLon). Flow = off-chain signed mint/redeem **attestation** (quote from Ondo API) + on-chain contract mints to whitelisted address against USDC. **No verified contract address or event signature (share+quote) found via public search.** docs.ondo.finance describes the attestation flow, not a public event ABI.

**Answer:** 24/7 issuer activity exists and is real capital at issuer price (the ideal top-weight witness), but the exact on-chain event emitting both share and quote amounts is **unverified**. 

**Impact (fallback adopted — ADR-010):** For the **mainnet showcase (Phase 11.M, stretch)**, use **StablePair + sibling v4 `Swap` events as primary witnesses**; treat a verified Ondo issuer event as a bonus to wire only if its ABI is confirmed on Etherscan first. **Testnet build is unaffected** — it uses `MockIssuer.Minted(address,uint256,uint256)` regardless. TODO before 11.M: locate GM token/manager contracts on Etherscan/BscScan, read ABI + recent logs, compute `offsetTicks`.

---

## G0.7 — weekend witness activity ✅ N/A (testnet-only, ADR-011)

> Mainnet-showcase concern only; out of scope. Testnet witness density is produced by the flow bot. Retained for reference.

**Question:** Enough weekend events for candidate mainnet witnesses → choose `minQuorumWeight`, `maxAgeClosed`.

**Evidence:** README §2.1 data: tokenized stocks did $3.96B weekend DEX volume Sept 2026 (~106× Nov 2025); majority of volume off-hours; Uniswap ~60% share. Per-pool weekend log counts require RPC queries against specific chosen-ticker pools — not run (mainnet showcase is a stretch; no ticker chosen yet).

**Answer:** Aggregate activity is ample; concrete per-pool counts to be measured against the chosen ticker's pools immediately before Phase 11.M.

**Impact:** Not blocking. Testnet uses mock witnesses + flow bot. Keep defaults `minQuorumWeight=4`, `minDistinctChains=2`, `maxAgeClosed` per source; **fallback** if real weekend events are sparse: lower `minQuorumWeight`, lengthen `maxAgeClosed`. Revisit in 11.M.

---

## G0.2 — Reactive UHI11 sponsor/track ✅

**Question:** Is Reactive a UHI11 sponsor / prize track?

**Evidence:** User confirmed (2026-11-18).

**Answer:** Yes — confirmed correct by the user.

**Impact:** Reactive integration pitched on the sponsor track as designed.

---

## G0.8 — third-party design attribution ✅ (resolved: none used)

**Question:** Any external project's design principles borrowed that would need permission or credit?

**Answer:** No. No third-party code is copied. The monotonic risk ratchet is domain-driven — closed-market gap risk can only grow until the market reopens, so the score ratchets up while CLOSED and resets at reconcile. No external attribution or permission needed.

**Impact:** None. Credits list = Gapguard (MIT), Maestro, horsefacts/trading-days (MIT) only.
