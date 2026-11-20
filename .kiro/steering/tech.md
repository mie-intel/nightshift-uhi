---
inclusion: always
---

# NightShift — tech context

> Versions marked `TBD@Phase2` are pinned after `make install` (README §16). Items marked **(Gate 0)** are unverified until `docs/verification.md` — read installed lib source before coding against the API.

## Stack (README §16)

| Tool / lib | Use | Version |
| --- | --- | --- |
| Foundry (forge/cast/anvil) | build, test, scripts | forge 1.7.1 |
| `Uniswap/v4-core` | PoolManager, types, `LPFeeLibrary`, `TickMath` | **transitive** via uniswap-hooks (`lib/uniswap-hooks/lib/v4-core`) |
| `Uniswap/v4-periphery` | `HookMiner`, `LiquidityAmounts`, test routers | **transitive** via uniswap-hooks (`lib/uniswap-hooks/lib/v4-periphery`) |
| `OpenZeppelin/uniswap-hooks` | `BaseHook`, `BaseOverrideFee`, `CurrencySettler` | v1.2.1 |
| `OpenZeppelin/openzeppelin-contracts` (v5) | `ERC20`, `ReentrancyGuard`, `Ownable2Step`, `Math`, `SafeCast` | v5.7.0 |
| `Reactive-Network/reactive-lib-omni` | `AbstractReactive`, `AbstractCallback`, `ISystemContract` | v0.1.0 |
| `foundry-rs/forge-std` | tests | v1.17.0 |
| Slither | static analysis | TBD@Phase14 |
| Node ≥20, pnpm, TypeScript, `viem` | recorder, flow bot, scripts | TBD@Phase12 |
| `better-sqlite3` / JSONL | recording store | TBD@Phase12 |
| Next.js (App Router) + wagmi + viem + TanStack Query + Tailwind + Recharts | dashboard | TBD@Phase13 |

- **v4-core/v4-periphery are NOT installed top-level** — we use the exact copies uniswap-hooks v1.2.1 bundles, so hook-base types match ours. `remappings.txt` points `@uniswap/v4-core/` → `lib/uniswap-hooks/lib/v4-core/`. (Top-level v4-core@v4.0.0 lacked `types/PoolOperation.sol` → removed.) CI checkout must be `submodules: recursive`.
- **solc is auto-detected per pragma** (no pin in default profile): destination `^0.8.26` and reactive `^0.8.29` compile in one run; observed solc 0.8.35 for the 0.8.29 unit. Versions locked in `contracts/foundry.lock`.
- Layout/remappings starting point: `uniswapfoundation/v4-template` (compare, don't blindly copy).

## Compiler settings (README §16.1)

- **Destination contracts** (hook, vault, registry, libraries, mocks): `pragma solidity ^0.8.26;` — **Controller `^0.8.29`** (AbstractCallback, ADR-014); `evm_version = "cancun"` (transient storage required). `[profile.default]`. v4 `PoolManager` pins `0.8.26` → tests deploy it from its artifact (ADR-014).
- **Reactive contract** (`NightShiftReactive`): `pragma solidity ^0.8.29;`, own `[profile.reactive]`, `evm_version = "cancun"` (G0.4 — Cancun-era confirmed; **verify by real Lasna deploy in Phase 4**; fallback `paris`/`shanghai` + no tstore in `react()`).
- Let Foundry auto-detect solc for deps. `fuzz runs 256`, `invariant runs 64`. `via_ir` only if needed.

## Reactive Omni essentials — VERIFIED from `reactive-lib-omni` source + docs (docs/verification.md G0.3)

- `SYSTEM = ISystemContract(payable(0x8888888888888888888888888888888888888888))`; `REACTIVE_IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad`.
- Reactive: inherit `AbstractReactive`; `react(IReactive.LogRecord calldata log_) external onlySystem` (**`calldata`**, not `memory`).
- `subscribe(chainId, contract, topic0, topic1, topic2, topic3)` — **6 args, all four topics**; wildcard = `REACTIVE_IGNORE`; `chainId=0`/`contract=0` = all. One subscription per criteria set (no OR).
- Callback: `SYSTEM.requestCallbackV_1_0(CallbackConfiguration_V_1_0{uint256 chainId; address recipient; uint64 gasLimit; bytes payload})`; payload = `abi.encodeWithSelector(IController.onX.selector, address(0), ...)`.
- **Auth (use BOTH, always):** callback fn `(address reactive_, ...) external onlyServiceProvider onlyCallbackSender(reactive_)`. `onlyServiceProvider` = `msg.sender == callbackProxy`; `onlyCallbackSender` = injected first-arg `== _CALLBACK_SENDER`. Constructor `AbstractCallback(callbackProxy_, callbackSender_)`.
- Legacy `Callback` event exists but is **deprecated** — use `requestCallback*`. No RVM in Omni.
- **Cron** lives on legacy sys contract `0x0000000000000000000000000000000000fffFfF`. Use **Cron100** topic0 `0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70` (~2 min). (Cron1 ~1s, Cron10 ~10s, Cron1000 ~17min, Cron10000 ~3h — see verification.md.) **Cron bills every tick even if `react()` no-ops.**
- **Funding/debt:** fund reactive via `SYSTEM.depositTo(reactiveAddr){value}` (lREACT Lasna / REACT mainnet); fund Controller via `callbackProxy.depositTo(controllerAddr){value}` in **destination native token** (ETH/BNB, never REACT). Expose `coverDebt()` → `_coverDebt()`. **Any debt > 0 blocks execution.** Base Sepolia faucet `0x2afaFD298b23b62760711756088F75B7409f5967` (1 ETH → 100 lREACT, max 5).
- **Gas:** callback min **100 000** (below = ignored); **`react()` capped at 900 000** (Reactive-tx limit) → keep witness math lean, vault loop on destination. Callback `gasLimit` defaults: onAnchor 2.5M (loops vaults, try/catch), onRegime 1.5M, onReconcile 2.5M, onCorporateAction 2.5M (tune). Fee `p_base·C·(g+K)`, failed callbacks still charged.

## Uniswap v4 essentials (README §9, §13.1)

- Dynamic fee: pool created with `fee = LPFeeLibrary.DYNAMIC_FEE_FLAG`; `beforeSwap` returns `fee | LPFeeLibrary.OVERRIDE_FEE_FLAG`. Fee units = **pips** (1 000 000 = 100%).
- Hook permissions used: `afterInitialize`, `beforeAddLiquidity`, `beforeSwap`, `afterSwap`. No return-delta flags.
- Address mined with `HookMiner` for those flags; deployed via CREATE2 deployer `0x4e59b44847b379578588920cA78FbF26c0B4956C`.
- `BaseHook` = OZ uniswap-hooks v1.3.0 (G0.5). **Extend `@openzeppelin/uniswap-hooks/src/fee/BaseOverrideFee.sol`** (free `NotDynamicFee` + override-fee `_beforeSwap`); override `getHookPermissions` to add `beforeAddLiquidity`+`afterSwap`; implement `_getFee`/`_afterSwap`/`_beforeAddLiquidity`.
- Transient storage stashes per-swap `tickBefore`/`away` between `beforeSwap` and `afterSwap`.

## Chains & addresses (README §18 — copy exactly; re-verify before deploy)

### Reactive Network (§18.1)
- Lasna (testnet): chainId `5318007`, RPC `https://lasna-rpc.rnk.dev/`, SYSTEM `0x8888888888888888888888888888888888888888`, explorer `https://lasna.reactscan.net`.
- Mainnet: chainId `1597`, RPC `https://mainnet-rpc.rnk.dev/`, same SYSTEM, explorer `https://reactscan.net`.
- lREACT faucet (Ethereum Sepolia): `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`. **Never mix mainnet/testnet.**

### Callback proxies (§18.2)
Unichain Sepolia (1301) `0x775c9B990ADe401060B78D0e98684eEf8d2466C1` · Base Sepolia (84532) `0x476F44b11F5C942c58f4c8E3d0300E5710743585` · Ethereum Sepolia (11155111) `0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4` · Robinhood Chain (4663) `0x476F44b11F5C942c58f4c8E3d0300E5710743585` · Ethereum (1) `0xFCE1F192F489c988392aBC16E91e359d540d94Fe` · BSC (56) `0xfc41eE9d3A836b41399BEcce83b06B3e5650f3BB` · Base (8453) `0xCc780DdE33f56f55dE778D42c930959374a4a068` · Unichain (130) `0x754120EC7a6eF81E4c5c835AA603C63Da64693E6` · Arbitrum (42161) `0xaee8d2deBaB5bE353bfec167C58a549923892e11`.
Supported Reactive **testnets**: Base Sepolia, Ethereum Sepolia, Unichain Sepolia, Lasna. Robinhood Chain & BSC are **mainnet-only** on Reactive.

### Uniswap v4 PoolManager (§18.3) — see README §18.3 for PositionManager/StateView/Quoter/Router
- Unichain Sepolia (1301): `0x00b036b58a818b1bc34d502d3fe730db729e62ac`
- Base Sepolia (84532): `0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408`
- Sepolia (11155111): `0xE03A1074c86CFeDd5C142C4F04F1a1536e203543`
- Robinhood Chain (4663): `0x8366a39cc670b4001a1121b8f6a443a643e40951`
- Ethereum (1): `0x000000000004444c5dc75cB358380D2e3dE08A90`
- BSC (56): `0x28e2ea090877bf75740558f6bfb36a5ffee9e9df`
- Permit2 everywhere: `0x000000000022D473030F116dDEE9F6B43aC78BA3`. Test routers (PoolSwapTest/PoolModifyLiquidityTest): README §18.3.

## Topology (README §18.5)

**Testnet (primary build target, ADR-015):** Destination = **Base Sepolia** (pool+hook+controller+vaults+control pools; sibling pool B also here as a separate market). Origin = Ethereum Sepolia (MockIssuer + sibling pool A). Reactive = Lasna. lREACT via Base Sepolia faucet `0x2afa…5967`. Explorer: `https://sepolia.basescan.org`.
**Mainnet showcase: OUT OF SCOPE** (ADR-011 — testnet-only; real Ondo is mainnet and can't be witnessed from Lasna). Issuer witness is always `MockIssuer` on Eth Sepolia.

## Commands (README §20)

`make install · build · test · test-scenarios · coverage · slither · fmt · deploy-testnet · fund-reactive · e2e-testnet · record · report · app`

## Env var names (README §19 — names only, no values)

Keys: `DEPLOYER_PRIVATE_KEY`, `REACTIVE_PRIVATE_KEY`, `FLOWBOT_PRIVATE_KEY`. RPCs: `RPC_ETH_SEPOLIA`, `RPC_BASE_SEPOLIA`, `RPC_UNICHAIN_SEPOLIA`, `RPC_LASNA`, `RPC_ROBINHOOD`, `RPC_REACTIVE_MAINNET`, `RPC_ETHEREUM`, `RPC_BSC`. Explorers: `ETHERSCAN_API_KEY`, `BASESCAN_API_KEY`, `UNISCAN_API_KEY`. Reactive: `REACTIVE_SYSTEM`, `LREACT_FAUCET_SEPOLIA`, `LREACT_FAUCET_BASE_SEPOLIA`, `CALLBACK_PROXY_BASE_SEPOLIA`, `CALLBACK_PROXY_UNICHAIN_SEPOLIA`, `CALLBACK_PROXY_ROBINHOOD`. Selector: `NETWORK` (testnet|mainnet).

## Technical constraints

- No upgradeable proxies. Vault never swaps (in-kind pro-rata flows only).
- Everything in **destination tick space** (1 tick ≈ 1 bp). Fee units in pips.
- Parameters live in `contracts/config/{testnet,mainnet}.json`, read via `vm.readFile` + `stdJson`; never hard-coded in logic. Deployed addresses → `deployments/{network}.json`.
