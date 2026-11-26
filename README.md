# NightShift

**Fair prices for tokenized stocks, even when Wall Street sleeps.**

NightShift is a Uniswap v4 hook with curator vaults. A Reactive Network contract watches other chains for the real
price of a stock and sends it to the pool, even when nobody is trading. No bot or trusted signer is needed.

UHI11 Hookathon · theme **Active Management & Curated Liquidity** · partner: **Reactive Network**

[![CI](https://github.com/mie-intel/nightshift-uhi/actions/workflows/ci.yml/badge.svg)](https://github.com/mie-intel/nightshift-uhi/actions/workflows/ci.yml)

| | |
|---|---|
| Demo video (≤ 5 min) | [Google Drive](https://drive.google.com/file/d/1bVh59BBmMB8QmSQQLiFIQHw_IQcTr2na/view?usp=sharing) |
| Live dashboard | https://nightshift-uhi.vercel.app (no wallet needed to view; or run locally: `make app`) |
| Repository | https://github.com/mie-intel/nightshift-uhi — branch **`main`** |
| Proof it runs on-chain | [`docs/recordings/e2e.md`](docs/recordings/e2e.md) (Etherscan → Reactscan → Basescan links) |

### For judges

| Requirement | Where |
|---|---|
| Uniswap v4 hook | [`contracts/src/hook/NightShiftHook.sol`](contracts/src/hook/NightShiftHook.sol), deployed and verified on Base Sepolia (addresses under [More detail](#more-detail)) |
| Partner integration and where it is in the code | [Reactive Network](#partner-integration-reactive-network) |
| Tests | 175 unit, fuzz and integration tests: `make test` (see [Run and test](#run-and-test)) |
| Frontend that uses the hook | [`app/`](app/): shows hook state and live fees, swaps through the hook, vault deposits |
| Built during the hookathon | All code in this repo. First commit: 18 Nov 2026 |
| Credits | [Credits](#credits) |

---

## The problem

Tokenized US stocks trade on-chain 24/7. The real stock only trades when the New York Stock Exchange (NYSE) is open.

When NYSE is closed, the real price still moves. The issuer keeps minting and redeeming tokens on one chain, and other
pools keep trading on another chain. But a Uniswap v4 pool has two blind spots:

- It **can't see other chains**.
- Its hook **only runs when someone trades**.

So the pool price drifts away from the real price. Liquidity providers (LPs) take risk they are not paid for, so they
pull their money out before the weekend. Spreads get wider, big trades fail, and traders leave Uniswap.

## How NightShift works

1. **Collect prices from other chains (Reactive Network).** Our reactive contract listens to the issuer's mint and
   redeem events on Ethereum Sepolia and to another Uniswap v4 pool for the same stock on Base Sepolia. It smooths
   each source over time, ignores sudden spikes, and only trusts the result when fresh prices come from **at least 2
   chains**. The result is the **fair price**. It sends this fair price to the pool, without anyone trading.
2. **Measure the risk and follow the market hours.** It also gives a risk score from 0 to 100%. The score grows the
   longer the market is closed, the more the sources disagree, and the further the pool is from the fair price. While
   the market is closed, the score can only go up. It also follows the NYSE calendar to switch the pool between
   open, closed and reopening.
3. **The hook checks every trade against the fair price.**
   - Trades that move the pool **toward** the fair price fix the price, so they are allowed. They pay part of the gap
     to LPs.
   - Trades that push the pool **away** from the fair price pay a higher fee that grows with risk, and their size is
     limited while the market is closed.
   - If the fair price gets too old, the hook switches to maximum protection.
4. **Curator vaults.** Curators run vaults that hold LP money. Each time a new fair price arrives, every vault moves
   its liquidity to that price, with no trade. When the market opens again, each vault is scored against simply
   holding the tokens (HODL). Curators earn a performance fee only when they beat their previous best.

```
Ethereum Sepolia            Reactive Network (Lasna)              Base Sepolia
MockIssuer.Minted ─┐        NightShiftReactive                    NightShiftController ──► NightShiftHook (v4 pool)
                   ├──────► prices → smoothing → 2-chain check   │  onAnchor / onRegime / ├─► NightShiftVault × N
Sibling v4 Swap ───┘        risk score · market hours ───────────┘  onReconcile           (move, snapshot, score)
(Base Sepolia)              requestCallbackV_1_0 ───── callback proxy ─┘
```

## How it compares to existing solutions

| | Normal pool | Gapguard-style hook | Maestro (UHI9) | **NightShift** |
|---|---|---|---|---|
| Knows the real price while NYSE is closed | no | no, only the last closing price | uses a crypto price feed, no market hours | **yes, from 2+ chains** |
| Updates the pool without a trade | no | no | yes (Reactive) | **yes (Reactive)** |
| Trades that fix the price | normal fee | base fee only if they move back to the **last closing price** | — | **allowed, pay part of the gap to LPs** |
| Trades that push the price away | normal fee | extra fee + size limit | — | **fee that grows with risk + size limit** |
| Who manages liquidity | nobody | nobody | one manager follows a price feed | **curator vaults, scored vs HODL** |

In our tests (same liquidity, same trades), both NightShift and the Gapguard-style hook are much better for LPs than a
normal pool. Gapguard-style LPs earn a little more (2–5 bps) because traders pay more. NightShift charges traders about
**31% less** on quiet and news weekends, and keeps the price **twice as close** to fair when the price sources stop.
It is a different trade-off, not a clear win. Full table under [More detail](#more-detail).

## Partner integration: Reactive Network

Reactive is the core of NightShift. The pool needs prices from more than one chain, delivered even when nobody trades,
and without a trusted middleman. Without Reactive we would need one bot per chain, a server to combine them, and a
trusted signer. With Reactive, listening, computing and sending all happen on-chain.

| What | Where |
|---|---|
| Reactive contract (runs on Lasna): listens to events, reads prices, computes the fair price and risk, follows market hours, sends callbacks | [`contracts/src/reactive/NightShiftReactive.sol`](contracts/src/reactive/NightShiftReactive.sol): `addSource` / `subscribeCron` (`SYSTEM.subscribe`), `react()` (entry point), `_computeQuorum`, `_refresh`, `_onCron`, `_sendAnchor` / `_sendRegime` / `_sendReconcile` (`SYSTEM.requestCallbackV_1_0`), `coverDebt`, `withdraw` |
| Receives the callbacks on Base Sepolia. Checks **both** that the call comes from Reactive's callback proxy (`onlyServiceProvider`) and that it was sent by our reactive contract (`onlyCallbackSender`) | [`contracts/src/controller/NightShiftController.sol`](contracts/src/controller/NightShiftController.sol): `onAnchor`, `onRegime`, `onReconcile`, updates the vaults, `coverDebt` |
| Deploy and setup (4 price sources + a timer) | [`contracts/script/02_DeployReactive.s.sol`](contracts/script/02_DeployReactive.s.sol), [`04_WireReactive.s.sol`](contracts/script/04_WireReactive.s.sol) |
| Local copy of the Reactive loop, used in tests | [`contracts/test/utils/ReactiveHarness.sol`](contracts/test/utils/ReactiveHarness.sol), [`contracts/src/mocks/MockSystemContract.sol`](contracts/src/mocks/MockSystemContract.sol) |
| Live proof (Reactscan + Basescan + Etherscan links) | [`docs/recordings/e2e.md`](docs/recordings/e2e.md) |

No other partner integrations.

## The Uniswap v4 hook

[`NightShiftHook.sol`](contracts/src/hook/NightShiftHook.sol) builds on OpenZeppelin `BaseOverrideFee`:

- `afterInitialize`: the pool must use a dynamic fee.
- `beforeSwap`: decides if the trade goes toward or away from the fair price and sets the fee for this trade.
- `afterSwap`: enforces the size limits.
- `quoteFee`: shows the fee before trading (used by the dashboard).
- Only the Controller can change the hook's state.

Vaults: [`contracts/src/vault/`](contracts/src/vault/) · math and NYSE calendar:
[`contracts/src/libraries/`](contracts/src/libraries/).

## Frontend

[`app/`](app/) is a dashboard for the live testnet deployment.

- **Without a wallet:** NYSE status, market state of the pool, pool price vs fair price, risk score, each price source,
  live buy/sell fees, a timeline of updates with explorer links, and the vault leaderboard.
- **With a wallet:** get demo tokens, swap through the hook (with clear error messages for the limits), and deposit
  into or withdraw from vaults.

## Run and test

```bash
git clone --recursive https://github.com/mie-intel/nightshift-uhi && cd nightshift-uhi
make install && make build
make test            # 175 unit, fuzz and integration tests, including a full simulated weekend
make test-scenarios  # normal pool vs Gapguard-style pool vs NightShift → docs/recordings/scenarios.csv
make app             # dashboard → http://localhost:5173
```

[`contracts/test/integration/WeekendLoop.t.sol`](contracts/test/integration/WeekendLoop.t.sol) plays a whole weekend
with all the real contracts (Reactive is simulated): Friday close → Saturday news on two chains → pool and vaults move
to the new price with no trade → a fixing trade is allowed, a too-far trade is blocked → Monday open → vaults scored
vs HODL → market open.

To make "weekend news" on testnet: `make news PRICE=104000000` (moves the issuer and the other pool to $104; needs a
funded testnet key in `.env`, never committed). Full deploy: `make deploy-testnet`.

## Credits

- **Gapguard** (Bytethebuilder, MIT): closed-market fee ideas (pricing a trade at the middle of a full allowed move).
  Our Gapguard-style test pool is based on it.
- **Maestro** (UHI9): moving liquidity with Reactive.
- **Veritas** (UHI9): idea of a Reactive-fed risk score that only goes up and sets the swap fee.
- **horsefacts/trading-days** (MIT): NYSE calendar reference (our calendar is rewritten from the published NYSE rules).
- OpenZeppelin uniswap-hooks, Uniswap v4-core/periphery, Reactive `reactive-lib-omni`.

---

## More detail

<details>
<summary><b>Test results: normal 0.30% pool vs Gapguard-style pool vs NightShift</b></summary>

From `make test-scenarios`. Same liquidity and same trades for all three pools. The market is closed all weekend. The
LP position covers ±12% around the start price. LP profit is measured against HODL at the reopen price, fees
included. The Gapguard-style pool uses the fee values from Gapguard's deploy script; its 15% hook cut is not modeled,
so its LPs keep the whole extra fee. Trades are scripted and do not react to fees. LPs hold a fixed position (vaults
moving liquidity is not part of this table).

| Scenario | Pool | Trades filled / blocked | LP profit vs HODL | Avg fee | Worst gap from fair price |
|---|---|---|---|---|---|
| S1 quiet weekend | normal | 11 / 0 | +3 bps | 0.30% | 15 ticks |
| | Gapguard-style | 11 / 0 | +6 bps | 0.50% | 15 ticks |
| | **NightShift** | 11 / 0 | +4 bps | 0.34% | 15 ticks |
| S2 news +4% on other chains | normal | 15 / 0 | **−25 bps** | 0.30% | 342 ticks |
| | Gapguard-style | 15 / 0 | −9 bps | 0.96% | 342 ticks |
| | **NightShift** | 15 / 0 | **−14 bps** | 0.66% | 342 ticks |
| S3 local buyers only, real price flat | normal | 12 / 0 | +31 bps | 0.30% | **1800 ticks (+19.7%)** |
| | Gapguard-style | 12 / 12 | +68 bps | 1.42% | 900 ticks (+9.4%) |
| | **NightShift** | 12 / 14 | **+65 bps** | 1.38% | **843 ticks (+8.8%)** |
| S5 price sources stop | normal | 10 / 0 | +10 bps | 0.30% | 160 ticks |
| | Gapguard-style | 10 / 0 | +19 bps | 0.59% | 160 ticks |
| | **NightShift** | 10 / 10 | **+21 bps** | 1.40% | **80 ticks** |

What it means: both closed-market hooks are much better for LPs than a normal pool. Compared with Gapguard-style,
NightShift is a different trade-off, not a clear win. Gapguard-style LPs earn a little more in S1–S3 (2–5 bps)
because traders pay more. NightShift charges traders about 31% less on quiet and news weekends, because it knows the
real price and doesn't charge trades that fix the price as if they were risky. When the price sources stop, NightShift
blocks more trades and keeps the price twice as close to fair (80 vs 160 ticks), at a higher fee.

</details>

<details>
<summary><b>How it's built (security, backups, fees, vaults)</b></summary>

- **Callback security:** the Controller uses both Reactive checks (`onlyServiceProvider` + `onlyCallbackSender`). The
  hook only accepts calls from the Controller. Price updates and market-hour updates each carry their own increasing
  number (`seq`), so an old or out-of-order callback is ignored.
- **Backups if Reactive is late:** anyone can call `syncRegime` (uses the NYSE calendar on Base Sepolia) or
  `forceReconcile` (after a timeout). The hook treats an old fair price as maximum risk.
- **Fees:** toward = base fee + 30% of the gap. Away = base fee + a part that grows with risk and distance; it is priced
  at the middle of a full allowed move, so splitting a trade into small pieces is never cheaper. All fees are capped at
  5% (hard limit 10%). While closed, away trades can move the price at most 100 ticks per block (less when risk is
  high). Toward trades can pass the fair price by at most 20 ticks.
- **Vaults:** deposits and withdrawals are in both tokens at the vault's current mix, so no price is needed and nobody
  can game an old price. Vaults never swap. Curators can't move funds or choose price ranges. Performance fee is at most
  20%, only above the previous best.
- **Settings** are in [`contracts/config/testnet.json`](contracts/config/testnet.json); addresses in
  [`deployments/testnet.json`](deployments/testnet.json). Design decisions are logged in
  [`.kiro/steering/decisions.md`](.kiro/steering/decisions.md).

</details>

<details>
<summary><b>Deployed contracts (testnet)</b></summary>

| Contract | Chain | Address |
|---|---|---|
| NightShiftHook (v4 hook) | Base Sepolia | [`0x78FEE4Cb1Ab46B04fBCaee3f77EC13178e2998C0`](https://sepolia.basescan.org/address/0x78FEE4Cb1Ab46B04fBCaee3f77EC13178e2998C0) |
| NightShiftController (receives callbacks, keeps the vault list) | Base Sepolia | [`0x6a9e1b5258aB0ca49028a893a149A44e5597C3D5`](https://sepolia.basescan.org/address/0x6a9e1b5258aB0ca49028a893a149A44e5597C3D5) |
| VaultFactory | Base Sepolia | [`0x68b00bF9D37195759bcAFC5990545dCe3c404193`](https://sepolia.basescan.org/address/0x68b00bF9D37195759bcAFC5990545dCe3c404193) |
| Vault · Steady Night (conservative) | Base Sepolia | [`0xD77C1c29405fEE4954192E69e6D08918A316620D`](https://sepolia.basescan.org/address/0xD77C1c29405fEE4954192E69e6D08918A316620D) |
| Vault · Balanced Night | Base Sepolia | [`0x866E6b84C55801461B63cdd83Fb0c4AF9945d0E5`](https://sepolia.basescan.org/address/0x866E6b84C55801461B63cdd83Fb0c4AF9945d0E5) |
| Vault · Night Owl (aggressive) | Base Sepolia | [`0xdC721A09BE20610Aa9aB23C01019833152f666fb`](https://sepolia.basescan.org/address/0xdC721A09BE20610Aa9aB23C01019833152f666fb) |
| DemoFaucet | Base Sepolia | [`0xc3E24C6CC9cf6f7102b58C798F96b93e7c743dD6`](https://sepolia.basescan.org/address/0xc3E24C6CC9cf6f7102b58C798F96b93e7c743dD6) |
| NightShiftReactive | Reactive Lasna | [`0x78bf302762a31839A3357283b56b0a150103f5D8`](https://lasna.reactscan.net/address/0x78bf302762a31839A3357283b56b0a150103f5D8) |
| MockIssuer (issuer price source) | Ethereum Sepolia | [`0x83Ec94D9fc79a41DF16652d4F359930D1dF22B58`](https://sepolia.etherscan.io/address/0x83Ec94D9fc79a41DF16652d4F359930D1dF22B58) |

Pool id: `0x1ada978597437ff76c2176b2f288e3d9b555ce303491ce33af19bb856f25a32a` · other pool id: `0xf916e0e61222b4cc4d1f3dbd0eb6fc0fde9154d7d5a816c98e86db2c894c1ba2`.

All addresses: [`deployments/testnet.json`](deployments/testnet.json). Contracts are verified on Etherscan / Basescan
and on Sourcify (Lasna).

</details>

<details>
<summary><b>Limits</b></summary>

- **Testnet only, demo tokens only.** Not real securities. The issuer is `MockIssuer`, a stand-in for a real issuer's
  24/7 mint/redeem desk. Trades in the demo pool are scripted.
- The fair price comes from real on-chain events on other chains, delivered by Reactive Network. But in this demo the
  price sources are not independent: we run `MockIssuer` and trade the other pool ourselves.
- Market-hour changes are checked on a timer of about 17 minutes, so the switch can be up to ~17 minutes late. Anyone
  can call `syncRegime` to apply it sooner.
- Each vault holds one liquidity position. Curator rules are fixed when the vault is created.
- Not audited. Hackathon code.

</details>

MIT License.
