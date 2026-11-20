# Demo video guide (≤ 5:00, your own voice)

Atrium rules: **max 5 minutes** (judges stop watching at 5:00), **no AI voice** (marked down + no Demo Day).
Cover: the problem · how the hook works · how it compares to existing solutions.

Target length **4:30** so you have slack. Speak slowly; it's fine to cut and re-record sections.

---

## Before you record (checklist)

- [ ] **lREACT topped up** on the reactive contract (Lasna) — otherwise callbacks stop. Check on the dashboard: the
      witness table shows "Quorum reached" after a news event. (`make fund-reactive`, then send to the contract.)
- [ ] **Best time: when NYSE is closed** (weekday after 21:00 UTC, or the weekend) so the pool shows *Closed*, away
      trades are capped, and risk is non-zero. Black Friday 27 Nov closes early at 18:00 UTC.
- [ ] Wallet (MetaMask/Rabby) on **Base Sepolia**, with a little Base Sepolia ETH and **Ethereum Sepolia** ETH.
- [ ] Use the **MockIssuer owner wallet** (the deployer) so the *Simulate weekend news* panel appears.
- [ ] Claim demo tokens once from the dashboard ("Get free demo tokens") so the swap works on camera.
- [ ] Do one dry run of *Simulate weekend news* ~10 minutes before recording (warms caches, confirms callbacks flow).
- [ ] Browser zoom 110–125%, close other tabs/notifications, 1080p, OBS or Loom. Mic close, quiet room.
- [ ] Tabs ready: dashboard · `docs/recordings/e2e.md` on GitHub · one Reactscan tab · one Basescan tab ·
      a terminal in the repo (font size up).

---

## Script with timings

### 0:00 – 0:30 · The problem
**Show:** dashboard hero ("Fair prices for tokenized stocks, even when Wall Street sleeps") + the *NYSE right now* card.

**Say (in your words):**
> "Tokenized stocks trade on-chain 24/7, but NYSE is closed most of the week. When it's closed, the real price still
> moves — the issuer keeps minting and redeeming on Ethereum, other pools trade on other chains — but a Uniswap v4
> pool can't see other chains, and its hook only runs when someone trades. So the pool drifts away from fair value,
> LPs carry gap risk they aren't paid for, and they pull liquidity every Friday."

### 0:30 – 1:05 · The idea
**Show:** the *How it works* card, then scroll to *Where the fair price comes from* (witness table).

> "NightShift fixes this with Reactive Network. A reactive contract watches the issuer on Ethereum Sepolia and a
> sibling Uniswap pool on Base, needs fresh prices from at least two chains, smooths them, and pushes a fair price into
> our pool — between trades, with no bot and no trusted signer. This table is read live from that contract: each
> source, its chain, its weight, the price it saw, and whether it's fresh."

### 1:05 – 2:20 · Live: news on two chains → the pool and the vaults move with no trade
**Do:** in *Simulate weekend news*, click **+2%** (or +5%). Approve the 3 wallet prompts (issuer price, issuer trade on
Ethereum Sepolia, sibling trade on Base).

> "Let's simulate weekend news: the issuer reprices up 2% on Ethereum Sepolia, and a sibling pool on Base trades to the
> same price. Nobody touches our pool."

**Show:** *Updates pushed into the pool* — a new row appears (refreshes every ~15 s): *Fair price $…* with ✓ Reactive
Network → ✓ Base Sepolia, "2s". Click **Reactive Network** (Reactscan tx) then **Base Sepolia** (Basescan tx).

> "Here is the reactive transaction on Lasna, and here is the callback that landed on Base about two seconds later and
> set the pool's fair price. That's the whole loop on-chain."

**Show:** the price card (pool price vs fair price, gap %) and the **Curator vaults** — the liquidity range moved to
the new price.

> "The curator vaults re-centered their liquidity onto the new fair price in the same callback. Still no trade on the
> pool."

*If the row takes longer than ~30 s:* say "Reactive delivers it in seconds; I'll cut ahead" and cut in the edit.

### 2:20 – 3:10 · Trades are priced against fair value
**Show:** *Trading fee now* card, then *Try a trade*.

> "Now the pool is below fair value. Buying dSTOCK moves it toward fair — that's repair flow, so it's served, and LPs
> keep 30% of the gap. Selling pushes it further away — that costs more, scaled by risk, and while the market is
> closed big pushes are blocked."

**Do:** Buy ~100 dUSD → success. Then switch to Sell with a large amount (e.g. your whole dSTOCK balance) → the
friendly "Blocked: this trade pushes the price too far…" message (when closed).

### 3:10 – 3:55 · Proof it works: tests + results
**Show:** terminal: `make test` (cut to the summary line: *all tests passed*), then the README **Results** table.

> "There are 160-plus tests, including a full weekend replay with every real contract. And the same order flow on a
> static pool versus NightShift: on news weekends LPs lose 44% less to stale-price arbitrage; when local buyers push the
> price away from fair, NightShift halves the premium and pays LPs twice as much; and if witnesses go silent it falls
> back to maximum protection instead of trusting a stale price."

### 3:55 – 4:30 · Why it's different + close
**Show:** README *What NightShift does* section or a simple slide.

> "Gapguard prices risk while the market is closed, but it gives closed-market prices zero weight. Maestro re-centers
> from a single signed feed. NightShift keeps the market working at a fair price from a quorum of on-chain witnesses
> on two chains — and makes curators accountable: at every reopen, each vault is scored against simply holding, and the
> curator only earns on gains above their high-water mark. Gapguard decides who gets paid when the market is closed;
> NightShift keeps the market working while it's closed."

> "Testnet, demo tokens, all contracts verified — links are in the README. Thanks!"

---

## Backup shots (record separately, splice in if live is slow)
- `make news PRICE=104000000` in the terminal, then refresh the dashboard.
- `cd contracts && forge test --match-contract WeekendLoopTest -vv` — prints the narrated weekend (Fri close → Sat news
  → repair → Mon reconcile).
- `docs/recordings/e2e.md` on GitHub with the explorer links.

## Don'ts
- Don't go over 5:00. Don't use AI voice/TTS. Don't call the demo flow "real users" — say "demo flow, real on-chain
  witnesses". Don't mention future plans as if built.
