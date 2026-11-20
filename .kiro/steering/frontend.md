---
inclusion: fileMatch
fileMatchPattern: ["app/**"]
---

# Dashboard (`app/`) spec (SPEC §22.3, ADR-016)

## Stack (light + fast — ADR-016)
Vite + React + TypeScript (static SPA, no SSR) · `viem` + `wagmi` (injected wallet only, no RainbowKit) · TanStack Query (wagmi peer) · Tailwind v4 (`@tailwindcss/vite`). Charts = hand-rolled SVG (no Recharts). System font stack (no web-font download). Minimal ABIs via `parseAbi` (never import forge artifacts into the bundle).

## Design rules (user preferences)
- Works first, **very easy to operate**; one page; obvious primary actions.
- Warm, calm palette (light brown / cream); **WCAG AA contrast** (≥ 4.5:1 body text, ≥ 3:1 large text/UI). Tokens live in `app/src/index.css` `@theme`.
- **Few eyebrow labels** (no small-caps kicker text above every heading). Plain headings + one-line explanations.
- Numbers in `tabular-nums`; prices in dUSD per dSTOCK.

## Rules
- **Read all addresses from `deployments/{network}.json`** — never hard-code.
- **No private keys in the frontend.** Read-only by default; wallet actions go through the user's wallet.
- A judge must open the URL and see live state **without a wallet**.
- Every loop shows explorer links: Etherscan (Sepolia `https://sepolia.etherscan.io`), Reactscan (Lasna `https://lasna.reactscan.net`), Basescan (Base Sepolia `https://sepolia.basescan.org`).
- Honesty (recorder.md): destination flow is scripted/demo; tokens are demo tokens.

## Page (single)
1. **Status:** NYSE open/closed (JS port of `NyseCalendar`) + countdown; pool regime from hook.
2. **Price:** pool price vs fair (anchor) price, gap %, anchor age; risk bar.
3. **Fees:** live `quoteFee` for buy / sell dSTOCK with toward/away tag.
4. **Swap:** buy/sell with fee preview; friendly errors for hook caps (`AwayMoveTooLarge`, `Overshoot`, `MarketHalted`).
5. **Reactive loops:** issuer mint (Sepolia) → reactive callback request (Lasna) → anchor updated (Base Sepolia), grouped by `seq`, with links.
6. **How it works:** 3 short steps. Owner-only "Simulate news" (issuer price ±x% + mint) shown only to the MockIssuer owner.
Later (if time): curators/vaults, epochs, scenario comparison.

## Data
On-chain reads via viem (public RPCs). Later: report JSON from `make report`. Deploy as static site (🛑 ask user before using any hosting account).
