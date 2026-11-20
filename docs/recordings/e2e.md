# Gate 1 — first live Reactive loop (20 Nov 2026)

A witness move on **Ethereum Sepolia** repriced the NightShift pool on **Base Sepolia** with **no trade on the pool**,
through a reactive contract on **Lasna**. End-to-end: **~3 s**.

| # | Step | Chain | Tx | Block time (unix) |
|---|---|---|---|---|
| 0 | Issuer price set to 102 dUSD (+2%) | Ethereum Sepolia | [0x33129211…8a18](https://sepolia.etherscan.io/tx/0x33129211069d0e527e4ac6a0c10d4ac719c436b63fa84c8164baf1e988d48a18) | — |
| 1 | `MockIssuer.mint(1 share)` → `Minted` (the witness) | Ethereum Sepolia | [0xfc4170ee…07a8](https://sepolia.etherscan.io/tx/0xfc4170ee28896136f3ca69570257e93204943194610813d5f88c0228cc3607a8) | 1795188672 |
| 2 | `NightShiftReactive.react()` → `requestCallbackV_1_0(onAnchor, seq 1, tick 230072)` | Lasna | [0x28c6b15e…a296e](https://lasna.reactscan.net/tx/0x28c6b15e67e01818415fd0034b0326a85335284c7514603809c54f53ea7a296e) | 1795188673 |
| 3 | Callback proxy → `NightShiftController.onAnchor` → `hook.setState` → `AnchorUpdated` | Base Sepolia | [0xab36b480…c615](https://sepolia.basescan.org/tx/0xab36b480b2d3e9f9b836fe8fcca13e4bf576cc26aca3e2fef3d571bce86cc615) | 1795188675 |

Result on-chain (hook `poolState`): `anchorTick = 230072` (was unset; pool tick 230271 = 100 dUSD), `lastSeq = 1`.
Pool price is now 2% below fair value → buying dSTOCK is the served *repair* direction; selling pushes away.
Callback gas 90 772; cost to the Controller ≈ 0.0000007 ETH; no debt.

Contracts: MockIssuer [`0x83Ec…2B58`](https://sepolia.etherscan.io/address/0x83Ec94D9fc79a41DF16652d4F359930D1dF22B58) ·
NightShiftReactive [`0x5c34…1c3b`](https://lasna.reactscan.net/address/0x5c34094CCc335B38092924C07cAC0D00D36a1c3b) ·
NightShiftController [`0x7c5b…1e66`](https://sepolia.basescan.org/address/0x7c5bAdFE78395927C29F683ad4a292DCD1B51e66) ·
NightShiftHook [`0x5786…d8C0`](https://sepolia.basescan.org/address/0x5786976C0527ECae71586b51226e86403343d8C0).
All verified (Etherscan/Basescan; Sourcify for Lasna). Reproduce: `make e2e-testnet` (see `deployments/testnet.json`).

---

# v1 — Witness Quorum across two chains (20 Nov 2026, live)

Reactive v1 (ADR-017) needs fresh witnesses on **≥ 2 chains** before it moves the pool. Witnesses: MockIssuer
mints/redeems on **Ethereum Sepolia** (weight 5) + a sibling Uniswap v4 pool on **Base Sepolia** (weight 2) + our own
pool's swaps (divergence only). Regime is driven by Cron1000 on Lasna.

| # | Step | Chain | Tx | Block time |
|---|---|---|---|---|
| 1 | Sibling pool B traded to $103 (`Swap`, 2nd chain of the quorum) | Base Sepolia | [0x9c801a1d…350a](https://sepolia.basescan.org/tx/0x9c801a1dec4c652eb726cab77e33d9cec8330dbf2478f5bab0463e0e49f8350a) | — |
| 1′ | First quorum → `onAnchor` seq 1 | Lasna → Base | [0xfca091a8…7322](https://lasna.reactscan.net/tx/0xfca091a85fd6b045259c2b3a7ef0682af68ee761c18964a14b18c57af5257322) → [0xab65f80e…d107](https://sepolia.basescan.org/tx/0xab65f80e78a263713da6629844e0a3e402eb2b1bbbcb15667f9cbb2bda92d107) | — |
| 2 | Issuer mints at $103 (`Minted`) | Ethereum Sepolia | [0xa93d628f…57f3](https://sepolia.etherscan.io/tx/0xa93d628f73c75b3a07ab46507052f4cce3e6179d2b2f9f8edc4e4f48068457f3) | 1795192212 |
| 3 | `react()` → quorum (2 chains) → `onAnchor` seq 2 | Lasna | [0x1231e598…b27e](https://lasna.reactscan.net/tx/0x1231e598a7dff6fa8b7725abc4eed0beb22e2f164266589b82ba85d4e082b27e) | 1795192212 |
| 4 | `NightShiftController.onAnchor` → `hook.setState` | Base Sepolia | [0x763ae01f…3061](https://sepolia.basescan.org/tx/0x763ae01fc0ea9743be481ddfba7e8e5c6d6fb10b0e0075dba58239c6126d3061) | 1795192214 |

Hook state after (seq 2): anchor $99.65 (EWMA still blending an earlier $99 issuer print toward $103), risk 11.25%
(OPEN: witness dispersion 90 ticks), regime OPEN. Issuer mint → pool update: **~2 s**.

v1 contracts (all verified): hook [`0x94D0…58c0`](https://sepolia.basescan.org/address/0x94D0aC748093AFe25A4811806c5232bdb93E58c0) ·
controller [`0x376B…EaeC`](https://sepolia.basescan.org/address/0x376B0580116EB96026397eb37e81767d92F0EaeC) ·
reactive [`0x0809…bB60`](https://lasna.reactscan.net/address/0x0809e4e6016eF2c587B1571DA6D193993F31bB60) ·
faucet [`0x2954…bF9d`](https://sepolia.basescan.org/address/0x29544B43bD7a87A950E131F4ad726A8Cf2c6bF9d).
Reproduce: `make news PRICE=104000000`.

---

# v2 — vaults move with the fair price, no trade (20 Nov 2026, live) ← current deployment

Same quorum (issuer on Ethereum Sepolia + sibling pool on Base Sepolia). One `onAnchor` callback now also re-centers
every registered curator vault (Controller fan-out, ADR-018).

| # | Step | Chain | Tx |
|---|---|---|---|
| 1 | Issuer mints at $104 (`Minted`) | Ethereum Sepolia | [0xf4b65c63…](https://sepolia.etherscan.io/tx/0xf4b65c639dbc6591f8902cdba1c39a643c474773e1fd95b25dd4f342ac974671) |
| 2 | Sibling pool trades to $104 (`Swap`) → 2nd chain completes the quorum | Base Sepolia | [0x1344dd0e…](https://sepolia.basescan.org/tx/0x1344dd0e905cf96c9c9c8cf9923e2aeaa6a190449293c8c24a2a37e71477794a) |
| 3 | `react()` → quorum → `onAnchor` seq 1 | Lasna | [0x4d426341…](https://lasna.reactscan.net/tx/0x4d4263416efca71c4a52ca2cd439b9322c46c4e12869c6935d484571f26d1357) |
| 4 | Controller → `hook.setState` + 3× `vault.rebalance` (one tx) | Base Sepolia | [0x567bd17f…](https://sepolia.basescan.org/tx/0x567bd17f5da908ee185ab2d133bc390f31b1916282077b76d2194cf68bcfef44) |

Result: pool fair price $104.00 (anchor tick 229878); the three vaults deployed liquidity around it with no trade on
the pool — Steady Night [229440, 230700], Balanced Night [229560, 230400], Night Owl [229620, 230100] (wider → narrower
by mandate; OPEN follow 50% / 70% / 100%). Landed ~5 s after the trades.
