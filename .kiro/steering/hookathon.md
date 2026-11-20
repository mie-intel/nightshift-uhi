---
inclusion: manual
---

# Hookathon logistics

Source: Atrium "Hookathon Guidelines & Process" page (snapshot `guideline.pdf`, read 20 Nov 2026).

## Dates
- Window: 16 Nov 2026 → **Final submission: 3 Dec 2026, 11:59 pm PST** (= 4 Dec 2026, 07:59 UTC).
- **Progress Update 1** ≈ 23 Nov (1 week in) · **Progress Update 2** ≈ 30 Nov (2 weeks in). Form links on the Atrium page; use Project ID `HK-UHI#-####` from the idea-form email. One submission per team.
- Demo Day: 11 Dec 2026.
- Project Update form (if scope changes): https://tally.so/r/m6lP9e
- Final Submission form: https://tally.so/r/mVNEAE — needs the **Project ID**. Project then appears in hooks.atrium.academy (edit access via team@atrium.academy).
- After results: Reactive Circuit bonus claim within 14 days if we place.

## Binary qualifications (fail any → not judged)
| Rule | What we must do |
| --- | --- |
| Public GitHub repo | Make repo public before submitting; link the **right branch** (`main`). |
| Demo video ≤ 5 min, **no AI voice** | Human voice. Judges stop at 5:00. AI voice = marked down + no Demo Day. |
| Valid Uniswap v4 hook | `NightShiftHook`. |
| Written & workable code during hookathon | All contract code is new (from 18 Nov 2026). |
| **README lists partner integrations + where in code** | Final README lists **only what is built**: Reactive → exact file/line links. **No future plans / theoretical integrations** (strip mainnet showcase, Ondo, Robinhood, etc. from the submission README or move to a clearly separate "spec" doc). |
| Originality / no copied code | Credit anything adapted (Gapguard, horsefacts/trading-days, v4-template) in NatSpec + README. |
| Tests **or** basic frontend | **Tests-first** (decided 20 Nov). Frontend optional, only if core done by ~29 Nov. |

## Scored evaluation (0–5 each, weighted)
| Criterion | Weight | How NightShift scores |
| --- | --- | --- |
| Original Idea | **30%** | Cross-chain witness quorum for off-hours tokenized stocks + curator accountability at reopen. Lead with the Gapguard contrast. |
| Unique Execution | **25%** | Reactive pushes state **between trades**; Cron regime; vault recenters with no destination trade. |
| Impact | 20% | Served repair flow, LPs stay over weekends; scenario table vs static pool. |
| Functionality | 15% | Core loop solid + tested beats broad and half-done. |
| Presentation | 10% | One clear loop in the video, not five layers. |

**Implication:** idea + execution = 55% → protect the Reactive loop and its on-chain proof. Functionality only 15% → cut breadth.

## Scope (MVP, decided 20 Nov — tests-first)
Must: Gate 1 real callback · hook (toward/away fees, move caps, stale fallback) · reactive (≥2 witness chains, quorum, Cron regime) · one vault (recenter on `onAnchor`, reconcile vs HODL + HWM) · scenarios S2, S3, S5, S6 vs static pool · ≥1 recorded live loop with explorer links · video.
Nice: Gapguard-style control pool, S1/S4/S8, one-page read-only dashboard.
Cut / slides only: corporate actions (S7), `migrate`, mandate timelocks, multiple presets, full leaderboard UI.

## Making tests judge-friendly (no frontend)
1. README top: `git clone --recursive … && make test` works on a clean clone.
2. Green CI badge.
3. Story-telling test names (`test_S2_newsWeekend_anchorFollowsWitnesses_vaultRecentersWithoutTrade`).
4. Scenario tests `console.log` a narrated timeline; show it in the video.
5. `make test-scenarios` writes a comparison table; embed it in README.
6. README "Verify in 2 minutes": reactive tx link + destination callback tx link + test command.

## Submission form checklist
- [ ] Submission Type: "Uniswap Hook Incubator (UHI)".
- [ ] Cohort: **your own** cohort (current if in incubator; graduation cohort if alumni — not "the hookathon").
- [ ] Partners: select **Reactive Network only if the integration actually runs** (never list planned integrations).
- [ ] Links: demo video (YouTube/Loom/Drive; accessible to all judges) + public GitHub repo on the right branch.

## Video must cover
The problem · how the hook works · how it compares to existing solutions (Gapguard, Maestro). ≤ 5 min, human voice.

## Live recording schedule (README §23, times UTC; ET = UTC−5 after 1 Nov 2026) — optional under MVP
| Window | Market | Record |
| --- | --- | --- |
| Wed 25 Nov 21:00 → Thu 26 Nov | **Thanksgiving closed** | Holiday regime |
| Fri 27 Nov 14:30 → 18:00 | **Black Friday early close** | Short session + early-close transition |
| Fri 27 Nov 18:00 → Mon 30 Nov 14:30 | Long closed | Main testnet recording |
| Mon 30 Nov 14:30 → 14:45 | Open window | Reconciliation + perf fee on camera |
(Fri 20 Nov weekend dry run missed — no deployable code yet.)

## Pitch one-liner
Gapguard decides who gets paid when the market is closed; NightShift keeps the market working at a fair price when it is closed — and makes curators accountable for it.

## Demo script outline (→ docs/demo-script.md)
1. Problem in 30 s (HIMS case, stranded anchor). 2. Close transition `onRegime(CLOSED)` in Reactscan + dest explorer. 3. Witness move on another chain → `onAnchor` → vault recenters **with no destination trade**. 4. Repair swap served at fair price; away swap pays + capped. 5. Reopen → reconcile → alpha vs HODL. 6. Scenario comparison table. 7. Prior-art slide.

## Credits that MUST appear (README §27)
- **Gapguard** (Bytethebuilder, MIT) — closed-market fee ideas + calendar rules.
- **Maestro** (UHI9) — Reactive-driven re-centering.
- **horsefacts/trading-days** (MIT) — NYSE calendar reference.

## Sponsor status
Reactive confirmed as sponsor (G0.2, user-confirmed).
