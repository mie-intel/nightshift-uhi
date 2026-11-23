# NightShift

**Fair prices for tokenized stocks, even when Wall Street sleeps.**
A Uniswap v4 hook + curator vaults, driven by a Reactive Network contract that brings the fair price in from other
chains — between trades, with no off-chain bot or signer relaying the price.

UHI11 Hookathon · theme **Active Management & Curated Liquidity** · partner integration: **Reactive Network**

[![CI](https://github.com/mie-intel/nightshift-uhi/actions/workflows/ci.yml/badge.svg)](https://github.com/mie-intel/nightshift-uhi/actions/workflows/ci.yml)

| | |
|---|---|
| Live dashboard | _Vercel URL — add after deploy_ |
| Demo video | _add link_ |
| Proof it runs on-chain | [`docs/recordings/e2e.md`](docs/recordings/e2e.md) (explorer links) |

---

## Description

Tokenized US stocks trade on-chain 24/7, but the underlying trades only in NYSE hours. When NYSE is closed, the
real price still moves — the issuer keeps minting and redeeming on one chain, sibling pools trade on another — but a
Uniswap v4 pool **can't see other chains** and its hook **only runs when someone trades**. So the pool drifts from
fair value: liquidity providers carry unpriced gap risk, pull liquidity on Friday, spreads widen, and volume leaves.

NightShift keeps the market working at a fair price while it's closed:

1. **Witness quorum (Reactive Network).** `NightShiftReactive` subscribes to the issuer's mint/redeem events on
   Ethereum Sepolia and to a sibling Uniswap v4 pool on Base Sepolia (plus our own pool's swaps). It smooths each
   source (EWMA, per-print influence cap), requires fresh prices from **≥ 2 chains**, takes a weighted median, and
   pushes the **fair price (anchor)** into the pool by callback — without anyone trading the pool.
2. **Gap risk + regime.** It also computes a 0–100% gap-risk score (time closed, witness disagreement, pool
   divergence, staleness) that only ratchets up while closed, and drives the market regime from the NYSE calendar on a
   Cron subscription: OPEN → CLOSED → reopening → reconcile → OPEN.
3. **The hook prices every trade against fair value.** Trades that move the pool **toward** the anchor (repair flow)
   are served and pay a share of the gap to LPs. Trades that push it **away** pay risk-scaled fees and are size-capped
   while closed. If the fair price goes stale, the hook falls back to maximum protection.
4. **Curator vaults.** Curators deploy vaults with per-regime mandates. When Reactive pushes a new fair price, every
   vault **re-centers its liquidity onto it with no trade**. At the reopen, each vault is scored **vs HODL at the
   witnessed open price**; curators earn a performance fee only on gains above their high-water mark.

## Partner integration — Reactive Network (where it is in the code)

| What | Where |
|---|---|
| Reactive contract (runs on Lasna): subscriptions, witness decoding, EWMA + quorum, risk, Cron regime, callbacks | [`contracts/src/reactive/NightShiftReactive.sol`](contracts/src/reactive/NightShiftReactive.sol) — `addSource` / `subscribeCron` (`SYSTEM.subscribe`), `react()` (entry point), `_computeQuorum`, `_refresh`, `_onCron`, `_sendAnchor` / `_sendRegime` / `_sendReconcile` (`SYSTEM.requestCallbackV_1_0`), `coverDebt`, `withdraw` |
| Callback receiver on Base Sepolia, authenticated with **both** `onlyServiceProvider` (callback proxy) and `onlyCallbackSender` (our reactive contract) | [`contracts/src/controller/NightShiftController.sol`](contracts/src/controller/NightShiftController.sol) — `onAnchor`, `onRegime`, `onReconcile`, fan-out to vaults, `coverDebt` |
| Deployment + wiring (4 witness sources + Cron1000) | [`contracts/script/02_DeployReactive.s.sol`](contracts/script/02_DeployReactive.s.sol), [`04_WireReactive.s.sol`](contracts/script/04_WireReactive.s.sol) |
| Local simulation of the Reactive loop used by tests | [`contracts/test/utils/ReactiveHarness.sol`](contracts/test/utils/ReactiveHarness.sol), [`contracts/src/mocks/MockSystemContract.sol`](contracts/src/mocks/MockSystemContract.sol) |
| Live proof (Reactscan + Basescan + Etherscan links) | [`docs/recordings/e2e.md`](docs/recordings/e2e.md) |

Uniswap v4: [`NightShiftHook.sol`](contracts/src/hook/NightShiftHook.sol) (OpenZeppelin `BaseOverrideFee`;
`afterInitialize`, `beforeAddLiquidity`, `beforeSwap`, `afterSwap`; dynamic LP fee override; transient-storage swap
stash), vaults in [`contracts/src/vault/`](contracts/src/vault/), pure math in
[`contracts/src/libraries/`](contracts/src/libraries/).

## Run & test

```bash
git clone --recursive https://github.com/mie-intel/nightshift-uhi && cd nightshift-uhi
make install && make build
make test            # 175 unit, fuzz and integration tests (incl. a full simulated weekend)
make test-scenarios  # static 0.30% pool vs Gapguard-style pool vs NightShift → docs/recordings/scenarios.csv
make app             # dashboard (Vite + React) → http://localhost:5173 — live testnet state, swaps, vaults
```

Demo "weekend news" on testnet: `make news PRICE=104000000` (issuer + sibling pool move to $104; needs a funded
testnet key in `.env`, never committed). Full deploy: `make deploy-testnet`.

## Credits

- **Gapguard** (Bytethebuilder, MIT) — closed-market fee ideas (away pricing at the midpoint of a full step).
- **Maestro** (UHI9) — Reactive-driven re-centering.
- **Veritas** (UHI9) — idea of a Reactive-fed risk score that only ratchets up and feeds the swap fee.
- **horsefacts/trading-days** (MIT) — NYSE calendar reference (our calendar is rewritten from the published NYSE rules).
- OpenZeppelin uniswap-hooks, Uniswap v4-core/periphery, Reactive `reactive-lib-omni`.

---

## More detail

<details>
<summary><b>Why Reactive is essential</b></summary>

The pool needs witness state from more than one chain, delivered between trades, with no off-chain relayer. Without
Reactive this would be one bot per chain plus an aggregator plus a signer. With Reactive, the cross-chain subscription,
the quorum math and the callback all run on-chain. In this testnet demo the witnesses themselves are not independent:
the deployer runs `MockIssuer` and trades the sibling pool, which sits on the destination chain.

</details>

<details>
<summary><b>Verify in 2 minutes (on-chain proof + tests)</b></summary>

1. Open [`docs/recordings/e2e.md`](docs/recordings/e2e.md): an issuer trade on Ethereum Sepolia → a `react()` tx on
   Lasna → the callback tx on Base Sepolia that set the pool's fair price, about 2–3 seconds end to end, no trade on
   the pool.
2. Run the tests:

   ```bash
   git clone --recursive https://github.com/mie-intel/nightshift-uhi && cd nightshift-uhi
   make test            # 175 unit, fuzz and integration tests
   make test-scenarios  # static vs Gapguard-style vs NightShift → docs/recordings/scenarios.csv
   ```

3. `contracts/test/integration/WeekendLoop.t.sol` replays a whole weekend with every real contract (Reactive simulated
   by the harness): Friday close → Saturday news on two chains → pool and vault repriced with no trade → repair swap
   served, overshoot blocked → Monday open window → reconciliation vs HODL → OPEN.

</details>

<details>
<summary><b>Results — static 0.30% pool vs Gapguard-style pool vs NightShift (same liquidity, same order flow)</b></summary>

From `make test-scenarios` (market closed all weekend; LP position ±12% around the start price; LP PnL measured vs
HODL at the reopen price after reopen arbitrage, fees included). The Gapguard-style pool uses the fee values from
Gapguard's deploy script; its 15% hook skim is not modeled, so its LPs keep the whole surcharge. Order flow is scripted
and does not react to fees, and LPs hold a fixed position (vault re-centering is not part of this table):

| Scenario | Pool | Trades filled / blocked | LP PnL vs HODL | Avg fee | Worst premium vs fair |
|---|---|---|---|---|---|
| S1 quiet weekend | static | 11 / 0 | +3 bps | 0.30% | 15 ticks |
| | Gapguard-style | 11 / 0 | +6 bps | 0.50% | 15 ticks |
| | **NightShift** | 11 / 0 | +4 bps | 0.34% | 15 ticks |
| S2 news +4% on other chains | static | 15 / 0 | **−25 bps** | 0.30% | 342 ticks |
| | Gapguard-style | 15 / 0 | −9 bps | 0.96% | 342 ticks |
| | **NightShift** | 15 / 0 | **−14 bps** | 0.66% | 342 ticks |
| S3 one-way local buying, fair price flat | static | 12 / 0 | +31 bps | 0.30% | **1800 ticks (+19.7%)** |
| | Gapguard-style | 12 / 12 | +68 bps | 1.42% | 900 ticks (+9.4%) |
| | **NightShift** | 12 / 14 | **+65 bps** | 1.38% | **843 ticks (+8.8%)** |
| S5 witness outage | static | 10 / 0 | +10 bps | 0.30% | 160 ticks |
| | Gapguard-style | 10 / 0 | +19 bps | 0.59% | 160 ticks |
| | **NightShift** | 10 / 10 | **+21 bps** | 1.40% | **80 ticks** |

Reading it: both closed-market designs clearly beat a static pool for LPs. Against Gapguard-style pricing, NightShift is
a different trade-off, not a strict win. Gapguard-style LPs earn slightly more in S1–S3 (2–5 bps) because traders pay
more. NightShift charges traders about 31% less on quiet and news weekends, since knowing the fair price means repair
flow is not priced as drift from a stale close. When witnesses go silent, NightShift blocks more flow and halves the
premium (80 vs 160 ticks), at a higher fee.

</details>

<details>
<summary><b>How it's built (auth, fallbacks, fees, vaults)</b></summary>

```
Ethereum Sepolia            Reactive Network (Lasna)              Base Sepolia
MockIssuer.Minted ─┐        NightShiftReactive                    NightShiftController ──► NightShiftHook (v4 pool)
                   ├──────► witnesses → EWMA → quorum (≥2 chains) │  onAnchor / onRegime / ├─► NightShiftVault × N
Sibling v4 Swap ───┘        risk ratchet · Cron1000 regime ───────┘  onReconcile           (recenter, snapshot, score)
(Base Sepolia)              requestCallbackV_1_0 ───── callback proxy ─┘
```

- **Callback auth:** both lib modifiers (`onlyServiceProvider` + `onlyCallbackSender`); the hook only accepts the
  Controller. Anchor and regime callbacks use separate monotonic `seq` channels (callbacks may arrive out of order).
- **Fallbacks:** anyone can call `syncRegime` (NYSE calendar on the destination chain) or `forceReconcile` (after a
  timeout) if Reactive is late; the hook treats a stale anchor as maximum risk.
- **Fees** (pips): toward = base + 30% of the gap; away = base + risk-scaled + drift at the midpoint of a full step
  (splitting a trade is never cheaper); all capped at 5% (hard cap 10%). Away moves capped at 100 ticks per block, shrinking with
  risk; toward trades may overshoot the anchor by at most 20 ticks.
- **Vaults:** in-kind pro-rata deposits/withdrawals (no price needed, no stale-NAV games), never swap; curators can't
  move funds or pick ticks; performance fee ≤ 20%, only above the high-water mark.
- **Parameters** live in [`contracts/config/testnet.json`](contracts/config/testnet.json); addresses in
  [`deployments/testnet.json`](deployments/testnet.json). Decisions are logged in
  [`.kiro/steering/decisions.md`](.kiro/steering/decisions.md).

</details>

<details>
<summary><b>Deployed contracts (testnet)</b></summary>

| Contract | Chain | Address |
|---|---|---|
| NightShiftHook (v4 hook) | Base Sepolia | [`0x78FEE4Cb1Ab46B04fBCaee3f77EC13178e2998C0`](https://sepolia.basescan.org/address/0x78FEE4Cb1Ab46B04fBCaee3f77EC13178e2998C0) |
| NightShiftController (callback receiver + vault registry) | Base Sepolia | [`0x6a9e1b5258aB0ca49028a893a149A44e5597C3D5`](https://sepolia.basescan.org/address/0x6a9e1b5258aB0ca49028a893a149A44e5597C3D5) |
| VaultFactory | Base Sepolia | [`0x68b00bF9D37195759bcAFC5990545dCe3c404193`](https://sepolia.basescan.org/address/0x68b00bF9D37195759bcAFC5990545dCe3c404193) |
| Vault · Steady Night (conservative) | Base Sepolia | [`0xD77C1c29405fEE4954192E69e6D08918A316620D`](https://sepolia.basescan.org/address/0xD77C1c29405fEE4954192E69e6D08918A316620D) |
| Vault · Balanced Night | Base Sepolia | [`0x866E6b84C55801461B63cdd83Fb0c4AF9945d0E5`](https://sepolia.basescan.org/address/0x866E6b84C55801461B63cdd83Fb0c4AF9945d0E5) |
| Vault · Night Owl (aggressive) | Base Sepolia | [`0xdC721A09BE20610Aa9aB23C01019833152f666fb`](https://sepolia.basescan.org/address/0xdC721A09BE20610Aa9aB23C01019833152f666fb) |
| DemoFaucet | Base Sepolia | [`0xc3E24C6CC9cf6f7102b58C798F96b93e7c743dD6`](https://sepolia.basescan.org/address/0xc3E24C6CC9cf6f7102b58C798F96b93e7c743dD6) |
| NightShiftReactive | Reactive Lasna | [`0x78bf302762a31839A3357283b56b0a150103f5D8`](https://lasna.reactscan.net/address/0x78bf302762a31839A3357283b56b0a150103f5D8) |
| MockIssuer (issuer witness) | Ethereum Sepolia | [`0x83Ec94D9fc79a41DF16652d4F359930D1dF22B58`](https://sepolia.etherscan.io/address/0x83Ec94D9fc79a41DF16652d4F359930D1dF22B58) |

Pool id: `0x1ada978597437ff76c2176b2f288e3d9b555ce303491ce33af19bb856f25a32a` · sibling pool id: `0xf916e0e61222b4cc4d1f3dbd0eb6fc0fde9154d7d5a816c98e86db2c894c1ba2`.

All addresses: [`deployments/testnet.json`](deployments/testnet.json). Contracts are verified on Etherscan / Basescan
and on Sourcify (Lasna).

</details>

<details>
<summary><b>Scope and limits</b></summary>

- **Testnet only, demo tokens only** — not real securities. The issuer is `MockIssuer` (a stand-in for an issuer's
  24/7 mint/redeem desk). Trades in the demo pool are scripted demo flow; the fair price comes from real on-chain events
  on other chains, delivered by Reactive Network.
- Vaults hold one concentrated position each. Curator mandates are fixed at deployment.
- Unaudited hackathon code.

</details>

<details>
<summary><b>Full design spec</b></summary>

The complete design document is in [`docs/SPEC.md`](docs/SPEC.md); decisions are logged in [`.kiro/steering/decisions.md`](.kiro/steering/decisions.md).

</details>

MIT License.
