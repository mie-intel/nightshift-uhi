---
inclusion: always
---

# NightShift — glossary (README §26)

| Term | Meaning |
| --- | --- |
| **Anchor** | Weighted-median fair price (in destination ticks) computed from fresh witnesses |
| **Witness** | An on-chain event source that reveals executable price information |
| **Quorum** | Enough fresh witness weight across ≥2 chains to trust the anchor |
| **Stranded anchor** | Fair-price information that exists on other chains but is invisible to the pool |
| **Regime** | OPEN, CLOSED, REOPEN_PENDING, HALTED |
| **Toward / away** | Swap direction relative to the anchor |
| **Gap Risk Score** | 0–10 000 bps closed-market risk; ratchets up while closed |
| **Mandate** | Curator's per-regime liquidity policy |
| **Epoch** | One closed period, from close to reconciliation |
| **Open tick** | Witnessed price during the first minutes of the regular session |
| **Alpha** | Vault NAV per share minus HODL per share at the open tick |
| **HWM** | High-water mark of cumulative alpha |
| **Callback proxy** | Reactive's destination-chain contract that delivers callbacks |
| **SYSTEM** | Reactive system contract `0x8888…8888` |
| **Lasna** | Reactive testnet |
| **Pips** | Uniswap fee units; 1 000 000 = 100% |
| **Tick** | log₁.₀₀₀₁ price; 1 tick ≈ 1 bp |
