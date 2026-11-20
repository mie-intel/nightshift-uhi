# Submission kit — copy/paste answers

Forms: Final Submission https://tally.so/r/mVNEAE · Project Update https://tally.so/r/m6lP9e ·
Progress Updates 1 & 2: links on the Atrium *Hookathon Guidelines & Process* page. Use your **Project ID**
(`HK-UHI#-####`) from the idea-form email. One submission per team.

## Final submission form

- **Submission type:** Uniswap Hook Incubator (UHI)
- **Cohort:** *your own* cohort (current if you're in the incubator; the cohort you graduated from if alumni)
- **Project name:** NightShift
- **One-liner:** Fair prices for tokenized stocks while Wall Street sleeps — a Uniswap v4 hook and curator vaults fed
  by a Reactive Network witness quorum across chains.
- **Partner integrations:** **Reactive Network** (select only this; it is fully built and live on Lasna).
- **Links:** GitHub https://github.com/mie-intel/nightshift-uhi (branch `main`) · demo video (YouTube/Loom, public) ·
  dashboard (Vercel URL).

**Description (short):**
> Tokenized stocks trade 24/7 on-chain but NYSE is closed most of the week. The fair price still moves on other chains
> (issuer mint/redeem, sibling pools), yet a v4 pool can't see other chains and its hook only runs when someone trades —
> so pools drift, LPs carry unpriced gap risk, and liquidity leaves. NightShift's reactive contract subscribes to
> witnesses on Ethereum Sepolia and Base Sepolia, requires a quorum across ≥2 chains, and pushes the fair price, a gap
> risk score and the market regime into the pool between trades. The hook serves repair flow (and recaptures part of
> the gap for LPs), charges risk-scaled fees and caps on trades that push away from fair value, and degrades to max
> protection if witnesses go stale. Curator vaults re-center liquidity onto the fair price on every update and are
> scored against HODL at each market reopen; curators earn a performance fee only above their high-water mark.

**How Reactive is used (where in code):**
> `contracts/src/reactive/NightShiftReactive.sol` (on Lasna): `SYSTEM.subscribe` for issuer `Minted`/`Redeemed`
> (Ethereum Sepolia), a sibling v4 `Swap` filtered by pool id (Base Sepolia), our own pool's `Swap`, and Cron1000;
> `react()` decodes witnesses, runs EWMA + weighted-median quorum + risk ratchet + calendar regime, and calls
> `SYSTEM.requestCallbackV_1_0` for `onAnchor`, `onRegime`, `onReconcile`.
> `contracts/src/controller/NightShiftController.sol` (on Base Sepolia) receives them with `onlyServiceProvider` +
> `onlyCallbackSender`, updates the hook and fans out to the vaults. Proof: `docs/recordings/e2e.md` (Reactscan +
> Basescan + Etherscan links; issuer trade → pool update in ~2–3 s).

**What's new during the hookathon:** everything in this repo (started 18 Nov 2026).

## Progress Update 1 (≈ 23 Nov)

> **Done:** core libraries (NYSE calendar with DST/holidays, price/tick math, witness math, risk ratchet, fee schedule),
> the v4 hook (dynamic fee toward/away, move caps, stale-anchor fallback), controller and reactive contract.
> **Gate 1 passed on 20 Nov:** a real issuer trade on Ethereum Sepolia → reactive tx on Lasna → callback on Base Sepolia
> set the pool's fair price in ~3 s (links in docs/recordings/e2e.md). Then a full witness quorum across two chains is
> live, plus a dashboard. **Next:** curator vaults with reopen scoring vs HODL, scenario comparison vs a static pool,
> demo video.

## Progress Update 2 (≈ 30 Nov)

> **Done since update 1:** curator vaults + factory (re-center on every Reactive update with no trade, close snapshot,
> reopen score vs HODL, performance fee above HWM), controller fan-out with try/catch, Cron-driven regime with calendar
> and timeout fallbacks, scenario suite vs a static 0.30% pool (LPs lose 44% less on news weekends, premium halved and
> LP PnL ~2× on one-way local flow, max protection on witness outage), dashboard with witness table, update timeline,
> vault leaderboard and deposits. 160+ tests. **Remaining:** recording the weekend live loop and the demo video.

## Before you submit (checklist)

- [ ] Repo public, link points to `main`.
- [ ] README: built integrations only (Reactive) with file links — done; add the Vercel + video links at the top.
- [ ] Video ≤ 5:00, your own voice, public link (see `docs/demo-script.md`).
- [ ] `make test` green on a clean clone (`git clone --recursive`).
- [ ] `deployments/testnet.json` matches what's live; contracts verified.
- [ ] Reactive contract funded (lREACT) so judges see live updates during judging.
