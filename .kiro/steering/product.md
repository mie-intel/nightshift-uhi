---
inclusion: always
---

# NightShift — product context

**Pitch (README §4.1):** The weekend price anchor of tokenized stocks isn't missing — it's stranded on other chains. NightShift uses Reactive to bring a quorum of witnesses, led by issuer execution, into Uniswap v4 pools, then lets curators compete to keep liquidity alive while Wall Street sleeps — with performance scored on-chain when the market reopens.

## The problem — the stranded anchor (README §2.2–2.3)

- Tokenized US equities trade 24/7 on-chain; the underlying trades only in NYSE sessions. A majority of DEX volume is outside market hours.
- Executable price info exists during closed hours (issuer mint/redeem on Ethereum/BNB, sibling pools, StablePair pools, 24/7 oracles) — but a v4 hook **only sees its own chain** and **only runs when someone trades**.
- Result: price drifts from fair value, LPs carry unpriced gap risk and pull liquidity on Friday, spreads widen, large trades revert or route elsewhere, volume leaves Uniswap.
- Fix needs a component that subscribes to events on many chains, computes on them, and pushes state into the pool **between trades** — no trusted off-chain signer. That is exactly a reactive contract; nothing simpler (one bot per chain + aggregator = the trusted signer we reject).

## Four layers +1 (README §4.2)

1. **Witness Quorum (Reactive).** Reactive contract subscribes to origin-chain events + the destination pool; normalizes to dest tick space, EWMA-smooths, weights by hard-to-fake-ness, computes weighted-median **anchor tick**, callbacks between trades.
2. **Gap Risk Score.** 0–10 000 bps risk from time-since-open-anchor, dispersion, pool-vs-anchor divergence, staleness. While CLOSED it only **ratchets up**; resets at reconcile.
3. **Curator marketplace.** Curators deploy vaults with per-regime mandates (open/closed/reopen); mandate changes timelocked; depositors pick a curator and migrate.
4. **Reopen reconciliation.** First regular-session witnessed price (open tick) scores each vault vs HODL; perf fee only on positive alpha above HWM; on-chain leaderboard.
5. **(+1) Corporate actions.** Issuer multiplier/split events → controlled halt + anchor rescale + forced vault recenter.

## How it increases transactions (README §4.3)

- LPs no longer flee on Friday → depth survives the weekend.
- Repair swaps (toward anchor) are **served** (modest gap-proportional fee), not reverted.
- Away swaps pay steep risk-scaled fees and are size-capped → LPs paid for gap risk, so they stay.
- Fair prices during the hours that already carry most tokenized-stock volume → more routing to Uniswap.

## Non-goals (README §4.4)

Not an oracle product (we don't publish prices for others). No real securities in demo pools (demo tokens only). No custody/KYC. No Solana/non-EVM witnesses (Reactive is EVM-only). No upgradeable proxies.

## Four project criteria — every feature must keep ALL green (README §1.2)

- [ ] 1. Solves a problem not solved yet (or very likely not).
- [ ] 2. Increases the number of transactions on Uniswap.
- [ ] 3. Fits the UHI11 theme.
- [ ] 4. Uses sponsor tech (Reactive Network) doing real work, not decoration.

## Reactive's three-question bar — every integration must pass (README §1.3)

- [ ] 1. Is the subscription doing **real work**?
- [ ] 2. Would the project be **simpler without Reactive**? (Answer must be **no**.)
- [ ] 3. Did it **actually run**? Proven by a reactive tx on Lasna/mainnet **plus the callback on the destination chain**, visible in explorers.

> At UHI9 only six projects cleared the "callback actually fired on-chain" floor. **First engineering milestone: a real callback landing on the destination chain (Gate 1).**

## UHI11 theme mapping (README §1.1) — Active Management & Curated Liquidity

| Theme bullet | NightShift component |
| --- | --- |
| Vault-managed hook modules | `NightShiftVault` per curator, hook-aware |
| Curated LP networks (follow a manager) | `CuratorRegistry` + depositor migration |
| Auto-rebalancing from off-chain signals / oracle triggers | Reactive Witness Quorum → `onAnchor` → vault rebalance |
| Perf fees, backtesting, strategy migration | Reopen reconciliation, alpha-vs-HODL + HWM, scenario replays, `migrate()` |

## Prior art one-liners + differentiation (README §3)

- **Gapguard** (Robinhood Chain, MIT): on-chain NYSE calendar + closed surcharge + ~1% move cap; closed-market prices get zero weight, large swaps revert, splits rigid.
- **Maestro** (UHI9, Reactive): reactive re-centers a pool from a single signed Pyth feed; no regime/curator layer.
- **Chainlink 24/7**: a price, not a liquidity policy — used as one low-weight witness.
- **StablePair + Ondo 24/7 mint/redeem**: arb path slow/costly; pools still can't see the anchor → treat as strongest witnesses.

**One-line differentiation:** Gapguard decides who gets paid when the market is closed; NightShift keeps the market working at a fair price when it is closed — and makes curators accountable for it.

## Target users

Curators (deploy vaults, earn perf fees), depositors/LPs (follow a curator, migrate), traders (served repair flow at fair price), issuers (tokenized-stock markets that stay liquid off-hours).

## Success metrics (README §21.3)

Per pool vs static / Gapguard-style control: swaps filled, reverts, LP PnL vs HODL (quote), fees earned, avg trader cost, |pool price − reopen price| at open, depth within ±2% over time. Scored across scenarios S1–S8.

## Hookathon dates

Window 16 Nov 2026 → **final submission 3 Dec 2026, 11:59 pm PST**. Demo Day 11 Dec 2026. Theme: Active Management & Curated Liquidity. Sponsor: Reactive Network (Omni), mandatory and core.
