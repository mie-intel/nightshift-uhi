---
inclusion: manual
---

# Hookathon logistics

## Dates
- Window: 16 Nov 2026 → **Final submission: 3 Dec 2026, 11:59 pm PST** (= 4 Dec 2026, 07:59 UTC).
- Demo Day: 11 Dec 2026.
- Project Update form (if scope changes): https://tally.so/r/m6lP9e
- Final Submission form: https://tally.so/r/mVNEAE — needs the **Project ID** from the idea-form email.
- After results: Reactive Circuit bonus claim within 14 days if we place.

## Deliverables (README §24)
- [ ] Project Idea form submitted (done) — keep the Project ID.
- [ ] Public GitHub repo with README + MIT license.
- [ ] Verified contracts on testnet (and mainnet if showcase).
- [ ] ≥1 documented Reactive loop: reactive tx + destination callback tx links.
- [ ] Demo video ≤ 5 min.
- [ ] Dashboard deployed (Vercel or similar).
- [ ] Final Submission form by deadline.

## Live recording schedule (README §23, times UTC; ET = UTC−5 after 1 Nov 2026)
| Window | Market | Record |
| --- | --- | --- |
| Fri 20 Nov 21:00 → Mon 23 Nov 14:30 | Weekend closed | Testnet dry run (S2-style news) |
| Wed 25 Nov 21:00 → Thu 26 Nov | **Thanksgiving closed** | Holiday regime |
| Fri 27 Nov 14:30 → 18:00 | **Black Friday early close** | Short session + early-close transition |
| Fri 27 Nov 18:00 → Mon 30 Nov 14:30 | Long closed | Main recording (mainnet showcase if ready, else testnet) |
| Mon 30 Nov 14:30 → 14:45 | Open window | Reconciliation + perf fee on camera |
- Flow bot runs a scripted news event Sat 28 Nov (sibling + issuer move) + mixed toward/away flow.

## Pitch one-liner
Gapguard decides who gets paid when the market is closed; NightShift keeps the market working at a fair price when it is closed — and makes curators accountable for it.

## Demo script outline (README §23; → docs/demo-script.md)
1. Problem in 30 s (HIMS case, stranded anchor). 2. Close transition `onRegime(CLOSED)` in Reactscan + dest explorer. 3. Witness move on another chain → `onAnchor` → vault recenters **with no destination trade**. 4. Repair swap served at fair price; away swap pays + capped. 5. Reopen → reconcile → leaderboard. 6. Three-pool comparison chart. 7. Prior-art slide.

## Credits that MUST appear (README §27)
- **Gapguard** (Bytethebuilder, MIT) — closed-market fee ideas + calendar rules.
- **Maestro** (UHI9) — Reactive-driven re-centering.
- **horsefacts/trading-days** (MIT) — NYSE calendar reference.

## Open gate: sponsor status
Reactive as UHI11 sponsor/prize track — confirm in UHI Discord (Gate 0.2). If not, still core design; pitch main track.
