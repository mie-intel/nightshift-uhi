---
inclusion: fileMatch
fileMatchPattern: ["app/**"]
---

# Dashboard (`app/`) spec (README §22.3)

## Stack
Next.js (App Router) + wagmi + viem + TanStack Query + Tailwind + Recharts. Pin versions at install → record in tech.md.

## Rules
- **Read all addresses from `deployments/{network}.json`** — never hard-code.
- **No private keys in the frontend.** Read-only by default; wallet actions (deposit/withdraw/migrate) go through the user's wallet.
- A judge must open the URL and see live state + recorded comparisons **without a wallet**.
- Every callback shows explorer links: Reactscan (Lasna `https://lasna.reactscan.net` / mainnet `https://reactscan.net`) + destination explorer (Base Sepolia `https://sepolia.basescan.org`, ADR-015).

## Pages
1. **Live:** regime badge, countdown to next transition, anchor vs pool price chart, risk gauge, witness table (source, chain, last tick, weight, freshness), latest callbacks w/ explorer links.
2. **Curators:** leaderboard (cumulative alpha/share, epochs, last epoch), mandate presets, deposit/withdraw/migrate.
3. **Epochs:** per-epoch reconciliation detail.
4. **Comparison:** static vs Gapguard-style vs NightShift from scenarios + live recordings.
5. **How it works:** diagram + one-paragraph explanation.

## Data
Reads report JSON produced by `make report` (recorder) + on-chain reads via viem. Deploy to Vercel (🛑 ask user for account).
