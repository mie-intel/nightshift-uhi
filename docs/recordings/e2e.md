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
