# TODO — NightShift (UHI11 Hookathon)

> **Claude, read this before anything else.**
>
> 1. `README.md` is the specification (the _what_ and _why_). This file is the plan (the _order_ and _done criteria_).
> 2. **Phase 0 comes first and is mandatory:** set up project context (`CLAUDE.md` → Kiro steering files). Write no contract code until Phase 0 is checked off.
> 3. Work top to bottom. Tick a box only when its **acceptance criteria** are met (tests green, files exist, links recorded).
> 4. Every time you learn something that contradicts the README or a steering file, fix the file and add an entry to `.kiro/steering/decisions.md`.
> 5. Items marked **🛑 ASK USER** need the user's explicit go-ahead (private keys, real funds, mainnet, external messages).
> 6. Keep commits small and conventional (`feat:`, `fix:`, `test:`, `docs:`, `chore:`), one logical change each.

---

## Timeline (today: Wed 18 Nov 2026 · deadline: Thu 3 Dec 2026, 11:59 pm PST)

| Dates        | Phases                  | Milestone                                                                                   |
| ------------ | ----------------------- | ------------------------------------------------------------------------------------------- |
| 18–19 Nov    | 0, 1, 2                 | Context ready, Gate 0 answers, repo builds                                                  |
| 19–21 Nov    | 3, 4 (walking skeleton) | **Gate 1: first real Reactive callback on Unichain Sepolia**                                |
| 21–25 Nov    | 5–9                     | Full contracts, local E2E harness, testnet redeploy                                         |
| 24–26 Nov    | 10                      | Scenarios S1–S8 + three-pool comparison                                                     |
| 25–30 Nov    | 11, 12                  | Live recording: Thanksgiving, Black Friday, weekend (testnet; mainnet showcase if approved) |
| 27 Nov–1 Dec | 13                      | Dashboard                                                                                   |
| 1–2 Dec      | 14                      | Security pass, docs, pitch, demo video                                                      |
| 3 Dec        | 15                      | Final submission                                                                            |

---

## Phase 0 — Project context setup (do this first)

Goal: any future Claude Code session (and Kiro, if the user opens the repo there) gets the same project context automatically. **Kiro steering files are the single source of truth for context; `CLAUDE.md` points to them.**

Design:

- Foundational steering (`product.md`, `tech.md`, `structure.md`, `glossary.md`) → `inclusion: always` in Kiro, and **imported** into `CLAUDE.md` with `@path` so Claude Code loads them at launch.
- Scoped steering (`inclusion: fileMatch` in Kiro) → mirrored for Claude Code by thin bridge files in `.claude/rules/` that use `paths:` frontmatter and `@import` the Kiro file. They load only when Claude works with matching files.
- Manual steering (`inclusion: manual`) → referenced from `CLAUDE.md` as "read when needed" (not imported).
- Keep imports one hop deep (CLAUDE.md → steering file). Never put `@imports` inside code blocks (they are not evaluated there).

### 0.1 Bootstrap the repo

- [ ] `git init` on branch `main`; add `.gitignore` (Foundry `out/`, `cache/`, `broadcast/*/dry-run`, `node_modules/`, `.next/`, `.env`, `*.sqlite`, `recorder/data/`), `LICENSE` (MIT), `.env.example` (copy README §19).
- [ ] Create the folder skeleton from README §17 (use `.gitkeep` in empty folders).
- **Done when:** `tree -a -L 3` matches README §17 (minus files created in later phases).

### 0.2 Foundational steering files (`inclusion: always`)

Front matter must be the **very first lines** of each file (no blank line before `---`). Keep each file tight — they load on every interaction. Source all content from README; do not invent.

- [ ] `.kiro/steering/product.md` (≤ 120 lines)
  ```yaml
  ---
  inclusion: always
  ---
  ```
  Must contain: one-paragraph pitch (README §4.1); the problem in 5 bullets ("stranded anchor", §2.2–2.3); the four layers + corporate actions (§4.2); how it increases transactions (§4.3); non-goals (§4.4); **the four project criteria** (§1.2) and **Reactive's three-question bar** (§1.3) as a checklist every feature must pass; UHI11 theme mapping table (§1.1); prior-art one-liners and the differentiation sentence (§3); target users (curators, depositors/LPs, traders, issuers); success metrics (§21.3 metrics); hookathon dates.
- [ ] `.kiro/steering/tech.md` (≤ 150 lines)
      Must contain: stack table (§16) with **pinned versions filled in after Phase 2**; compiler settings (0.8.26+/cancun for destination, 0.8.29 profile for reactive); Reactive Omni essentials (SYSTEM address, `react(LogRecord memory) onlySystem`, `SYSTEM.subscribe`, `SYSTEM.requestCallbackV_1_0`, first-arg identity rule, no `Callback` event, no RVM); Uniswap v4 essentials (dynamic fee flag + override flag, hook permissions used, HookMiner + CREATE2 deployer, transient storage for per-swap stash, fee units in pips); chain/addresses tables (§18) — copy exactly; topology (§18.5); commands (§20); env var names (§19, no values); technical constraints (no proxies, no vault swaps, in-kind flows, tick space everywhere, params in config JSON).
- [ ] `.kiro/steering/structure.md` (≤ 100 lines)
      Must contain: repo tree (§17); where each contract lives and what it owns; naming conventions (contracts, libraries, tests `X.t.sol`, scenarios `Scenario_SN_Name.t.sol`, scripts numbered); import patterns (remapping aliases, interfaces in `src/interfaces/`, shared structs/enums only in `libraries/Types.sol`); config files and `deployments/*.json` layout; docs layout.
- [ ] `.kiro/steering/glossary.md` (≤ 50 lines) — copy README §26.

### 0.3 Scoped steering files (`inclusion: fileMatch`)

Front matter template (pattern may be a string or a list):

```yaml
---
inclusion: fileMatch
fileMatchPattern: ["contracts/**/*.sol"]
---
```

- [ ] `solidity.md` — `contracts/**/*.sol`: pragma rules; custom errors; NatSpec on externals; `immutable`/`constant` use; events for every state change; checks-effects-interactions; `SafeCast`; no `tx.origin`; no unbounded loops (cap constants); explicit visibility; gas notes; formatting via `forge fmt`.
- [ ] `uniswap-v4-hook.md` — `contracts/src/hook/**`, `contracts/src/libraries/FeeMath.sol`: README §9 + §13.1 hook spec; permissions and mined address flags; dynamic fee mechanics; transient storage stash between `beforeSwap` and `afterSwap`; direction rules; move caps; stale-anchor fallback; `quoteFee` view; reference to `ControlClosedSurchargeHook` and Gapguard credit.
- [ ] `reactive.md` — `contracts/src/reactive/**`, `contracts/src/controller/**`, `contracts/src/libraries/{WitnessMath,RiskMath,PriceMath}.sol`: README §7, §8, §13.2, §14, §18.1–18.2; callback authentication; seq/epoch rules; debounce; Cron usage; funding; **the "callback must actually fire" rule**; Lasna vs mainnet never mixed.
- [ ] `vault-curation.md` — `contracts/src/vault/**`, `contracts/src/registry/**`: README §10, §11, §12; mandate struct and presets; in-kind flows; rebalance algorithm; snapshot/reconcile math; HWM; migration; role table.
- [ ] `testing.md` — `contracts/test/**`: README §21; ReactiveHarness design; scenario list S1–S8 with expected behavior; metrics; naming; fuzz/invariant conventions; "every bug fix gets a regression test".
- [ ] `security.md` — `contracts/src/**`: README §15 threats table + invariants; disclaimers; "ASK USER before mainnet".
- [ ] `frontend.md` — `app/**`: README §22.3 pages; stack; read addresses from `deployments/*.json`; explorer link formats; no private keys in the frontend.
- [ ] `recorder.md` — `recorder/**`: README §22.1–22.2; idempotent, resumable; storage format; flow bot honesty rule (scripted destination flow, real witnesses on mainnet).

### 0.4 Manual steering files (`inclusion: manual`)

- [ ] `decisions.md` — ADR log. Template per entry: `## ADR-NNN Title` · Date · Status · Context · Decision · Consequences. Pre-fill:
  - ADR-001 Reactive Omni API (no RVM, `SYSTEM` callbacks) is the target.
  - ADR-002 All prices in destination tick space.
  - ADR-003 Vault flows are in-kind pro-rata; vault never swaps.
  - ADR-004 Fee semantics: toward = repair flow served with gap capture; away = steep + capped (refines the "toward stays cheap" wording in the idea form).
  - ADR-005 Testnet topology (Unichain Sepolia destination; Sepolia + Base Sepolia origins; Lasna).
  - ADR-006 Destination calendar fallback + anchor staleness for defense in depth.
- [ ] `hookathon.md` — dates and deadlines (UTC and PST), forms (Project Update https://tally.so/r/m6lP9e, Final https://tally.so/r/mVNEAE), deliverables checklist (README §24), live recording schedule (§23), pitch one-liner, demo script outline, credits that must appear (Gapguard, Maestro, trading-days).

### 0.5 Claude Code bridges (`.claude/rules/`)

- [ ] One bridge per scoped steering file, same glob as the Kiro `fileMatchPattern`. Template (`.claude/rules/reactive.md`):

  ```markdown
  ---
  paths:
    - "contracts/src/reactive/**"
    - "contracts/src/controller/**"
    - "contracts/src/libraries/WitnessMath.sol"
    - "contracts/src/libraries/RiskMath.sol"
    - "contracts/src/libraries/PriceMath.sol"
  ---

  Source of truth: @../../.kiro/steering/reactive.md
  ```

  Create: `solidity.md`, `uniswap-v4-hook.md`, `reactive.md`, `vault-curation.md`, `testing.md`, `security.md`, `frontend.md`, `recorder.md`.

- [ ] Never duplicate content in bridges — only frontmatter + one import line. If a bridge's glob and the Kiro pattern drift apart, fix both.

### 0.6 `CLAUDE.md` (project root, ≤ 150 lines)

- [ ] Create with this structure (adapt wording, keep the imports as plain lines, not in code blocks):

  ```markdown
  # NightShift — Claude Code instructions

  Curated liquidity for tokenized stocks while Wall Street sleeps. Uniswap v4 hook + Reactive Network (Omni). UHI11 Hookathon, theme Active Management & Curated Liquidity. Deadline 3 Dec 2026 11:59 pm PST.

  ## Always-on context (Kiro steering is the source of truth)

  @.kiro/steering/product.md
  @.kiro/steering/tech.md
  @.kiro/steering/structure.md
  @.kiro/steering/glossary.md

  ## Scoped context

  Loaded automatically through `.claude/rules/` when you touch matching files:
  hook → uniswap-v4-hook · reactive/controller → reactive · vault/registry → vault-curation · tests → testing · any src → security, solidity · app → frontend · recorder → recorder.

  ## Read on demand

  - Full spec: README.md (section numbers are stable — cite them in commits/PRs)
  - Plan and status: TODO.md
  - Decisions: .kiro/steering/decisions.md
  - Deadlines, forms, pitch: .kiro/steering/hookathon.md

  ## Working rules

  1. Follow TODO.md order; tick boxes only when acceptance criteria pass.
  2. Before coding against a library, read its installed source (reactive-lib-omni, uniswap-hooks, v4-core/periphery).
  3. Parameters live in contracts/config/\*.json, never hard-coded in logic.
  4. Every feature must pass the 4 project criteria + Reactive's 3 questions (product.md).
  5. `make fmt && make test` before every commit; never commit .env or keys.
  6. 🛑 Ask the user before: using private keys, any mainnet transaction, spending real funds, contacting anyone.
  7. When reality contradicts README/steering: fix the file + add an ADR.
  8. Prefer the smallest change that makes a test pass; no proxies; no vault swaps.

  ## Commands

  make install · make build · make test · make test-scenarios · make deploy-testnet · make e2e-testnet · make record · make report · make app
  ```

- [ ] Optional `AGENTS.md` (2–3 lines) pointing other agents to `CLAUDE.md` and `.kiro/steering/`.

### 0.7 Verify context loading

- [ ] Self-check: every `@` path in `CLAUDE.md` and `.claude/rules/*.md` resolves to an existing file (write a tiny script `scripts/check-context.sh` that greps `@` lines and tests file existence; run it in CI later).
- [ ] 🛑 ASK USER to run `/memory` in Claude Code and confirm the four steering files appear; if they use Kiro, confirm the Steering panel lists all files with the right inclusion modes.
- [ ] Commit: `chore: project context (CLAUDE.md + Kiro steering)`.
- **Done when:** check script passes, user confirmed loading, commit exists.

---

## Phase 1 — Gate 0 verifications (README §25)

Output: `docs/verification.md` with one section per item: question, evidence (links, ABI snippets, tx hashes), answer, impact.

- [x] **G0.3 (blocking)** Install `reactive-lib-omni` (can be done in a scratch Foundry project if Phase 2 isn't done) and document: `AbstractReactive` API, `onlySystem`, `LogRecord` fields, `ISystemContract.subscribe` signature, `REACTIVE_IGNORE`, Cron topic names + hashes and intervals, `AbstractCallback` constructor + modifiers on the destination, how reactive and callback contracts are funded/charged (and how debt is repaid). Update `tech.md` + `reactive.md`.
- [x] **G0.4** EVM version to use for Lasna/mainnet deployments. → `cancun` (verify by Lasna deploy, Phase 4).
- [x] **G0.5** Which `BaseHook` to use; record exact import paths. → OZ uniswap-hooks `BaseOverrideFee`.
- [x] **G0.6** Max callback gas limit and per-callback cost; decide single `onAnchor` loop vs per-vault callbacks (ADR). → min 100k, react() ≤900k; single onAnchor loop on destination (ADR-009).
- [x] **G0.1** N/A for our scope — testnet-only, issuer = MockIssuer (real Ondo is mainnet; ADR-011).
- [x] **G0.7** N/A for our scope — real weekend witnesses were a mainnet-showcase concern; testnet uses flow bot (ADR-011).
- [x] **G0.2** Reactive sponsor status — confirmed by user. (G0.8 removed: no third-party design attribution used.)
- **Done when:** `docs/verification.md` complete; README/steering/ADRs updated.

---

## Phase 2 — Scaffolding and tooling

- [x] `contracts/` Foundry project: `foundry.toml` with `[profile.default]` (src, out, libs, `evm_version = "cancun"`, `via_ir` only if needed, fuzz runs 256, invariant runs 64) and `[profile.reactive]` (0.8.29 settings per G0.4); `fs_permissions` for `config/` and `../deployments/`.
- [x] Install deps (README §16.1); write `remappings.txt` (`@uniswap/v4-core/`, `@uniswap/v4-periphery/`, `@openzeppelin/uniswap-hooks/`, `@openzeppelin/contracts/`, `@reactive/`, `forge-std/`).
- [x] `contracts/config/testnet.json` and `mainnet.json` with all parameters from README §7–§11 (pool params, quorum, risk, debounce, mandates presets, gas limits).
- [x] `Makefile` with all targets in README §20 (stubs allowed for later phases, but must exit non-zero with a clear message).
- [x] pnpm workspace (`pnpm-workspace.yaml`) with `recorder/` and `app/` packages (empty shells).
- [x] GitHub Actions `ci.yml`: `forge fmt --check`, `forge build`, `forge test`, `scripts/check-context.sh`, `pnpm -r lint`, `pnpm -r build`.
- [x] Fill pinned versions into `.kiro/steering/tech.md`.
- **Done when:** `make install && make build && make test` pass on a clean clone; CI green.

---

## Phase 3 — Core libraries (minimum for the skeleton)

- [x] `Types.sol`: `Regime`, `SourceKind`, `PoolConfig`, `RegimeMandate`, `Mandate`, `WitnessSource`, `EpochResult`.
- [x] `PriceMath.sol` + tests (ratio→tick round trip within 1 tick; inversion; decimals).
- [x] `WitnessMath.sol` + tests (weighted median vs brute force fuzz; EWMA bounds; clamp).
- [x] `NyseCalendar.sol` + tests (all 2026–2027 holidays/early closes/DST; Thanksgiving 26 Nov 2026 closed; 27 Nov 2026 closes 18:00 UTC). Credit Gapguard/trading-days in NatSpec header.
- [x] `RiskMath.sol` + tests (ratchet monotonic fuzz).
- [x] `FeeMath.sol` + tests (direction table; caps; split-swap never cheaper fuzz).
- **Done when:** all library tests green; coverage of libraries ≥ 90% lines. ✅ 20 Nov: 72 tests green, libraries 99.45% lines. `NyseCalendar.nextTransition` deferred (dashboard-only, ADR-013).

---

## Phase 4 — Walking skeleton → **Gate 1: first real callback** (target: Sat 21 Nov)

Smallest end-to-end loop on real testnets, before building full features.

- [ ] `DemoToken`, `MockIssuer` (README §13.3).
- [ ] `NightShiftHook` v0: permissions, dynamic fee required, `setState` (onlyController), fee = `baseClosed` + simple away surcharge; emits `SwapObserved`.
- [ ] `NightShiftController` v0: authenticated `onAnchor` → `hook.setState`; `seq` check.
- [ ] `NightShiftReactive` v0: subscribe to `MockIssuer.Minted` on Ethereum Sepolia; on event compute tick (PriceMath), request `onAnchor` callback to Unichain Sepolia.
- [ ] Scripts 00–03 minimal; `deployments/testnet.json` written by scripts.
- [ ] 🛑 ASK USER for `.env` with testnet keys/RPCs and to fund the deployer (SepETH, Base Sepolia ETH, Unichain Sepolia ETH); then run `make fund-reactive`.
- [ ] Deploy; trigger `MockIssuer.mint` at a new price; observe reactive tx on Lasna and callback tx on Unichain Sepolia; `AnchorUpdated` emitted.
- [ ] Record the four links in `docs/recordings/e2e.md`.
- **Done when (Gate 1):** a reactive tx and its destination callback are visible in explorers. **If this fails by Sun 22 Nov:** stop feature work, debug only this loop, and 🛑 ASK USER whether to switch to the fallback idea (event-window liquidity for token unlocks: Reactive watches vesting-release events and triggers vault liquidity — it reuses the reactive contract, controller and vault code).

---

## Phase 5 — Full hook

- [ ] Full fee schedule (README §9.2) via `FeeMath`, per-pool `PoolConfig` from registry.
- [ ] Transient-storage stash of `tickBefore`/`away` between `beforeSwap` and `afterSwap`.
- [ ] Move caps + overshoot (§9.3) in `afterSwap`.
- [ ] Stale-anchor fallback (§9.4) + `AnchorStale` event.
- [ ] `setRegime`, `applyCorporateAction`, `HALTED` revert.
- [ ] `beforeAddLiquidity` `curatedOnly` gate.
- [ ] `quoteFee` view.
- [ ] Unit + fuzz tests per README §21.1; gas snapshot (`forge snapshot`).
- **Done when:** hook tests green; fee never exceeds caps under fuzz.

---

## Phase 6 — Controller and Reactive contract (full)

- [ ] Controller: `onAnchor`, `onRegime`, `onReconcile`, `onCorporateAction` with auth + seq/epoch checks; per-vault `try/catch`; `syncRegime` and `forceReconcile` fallbacks.
- [ ] Reactive: source registry (`addSource`/`disableSource` → `SYSTEM.subscribe`); decoders for `V4_SWAP`, `V3_SWAP`, `ISSUER_MINT/REDEEM`, `ORACLE`, `SELF`, `ISSUER_ACTION`; EWMA + caps; quorum; dispersion; risk (with ratchet); debounce; heartbeat; regime detection on Cron; open window; reconcile timeout; corporate actions; events (§14.4).
- [ ] `MockSystemContract` for tests.
- [ ] Unit tests for every decoder and rule (crafted `LogRecord`s).
- **Done when:** controller + reactive unit tests green.

---

## Phase 7 — Local end-to-end `ReactiveHarness` (README §21.2)

- [ ] Harness: etch SYSTEM, convert origin events to `LogRecord`s, call `react()`, relay queued callbacks with identity overwrite under `vm.prank(callbackProxy)`, warp for Cron.
- [ ] Integration test: close → witness move → anchor → (vault stub) → reopen → reconcile.
- **Done when:** integration test green and readable (it doubles as documentation).

---

## Phase 8 — Vaults, factory, registry

- [ ] `CuratorRegistry` (pool registration, timelocked config, vault registry, leaderboard storage, `migrate`).
- [ ] `NightShiftVault`: in-kind pro-rata `deposit`/`withdraw`; `unlockCallback` + `modifyLiquidity` + `CurrencySettler`; core/wide positions with salts; `rebalance` algorithm (§10.3); mandate timelock; views.
- [ ] `VaultFactory`.
- [ ] Mandate presets (Conservative/Balanced/Aggressive) in config + script `05_CreateCuratorVaults`.
- [ ] Unit, fuzz and invariant tests (README §15.2 #5).
- **Done when:** vault invariants hold under invariant testing; harness test now uses real vaults.

---

## Phase 9 — Reconciliation, performance fees, corporate actions

- [ ] `snapshotClose` per-share composition.
- [ ] `reconcile` math (§11.3), HWM, curator share minting, `EpochReconciled`, registry record.
- [ ] Corporate action flow end to end (§12).
- [ ] Tests incl. two-epoch HWM case (S8) and split (S7).
- **Done when:** S7 and S8 logic tests green.

---

## Phase 10 — Scenarios and comparison (README §21.3)

- [ ] `ControlClosedSurchargeHook` (Gapguard-style, credited) + static control pool setup helper.
- [ ] Scenario tests S1–S8, each against static / Gapguard-style / NightShift with identical liquidity and flows.
- [ ] Metrics writer → `docs/recordings/scenarios.csv` (+ JSON) via `make test-scenarios`.
- [ ] Tune default parameters until NightShift meets the expectations column; record final values + reasoning in an ADR.
- **Done when:** CSV produced; each scenario's expectation met or the gap explained in an ADR.

---

## Phase 11 — Testnet full deployment and live recording

- [ ] Redeploy full system on testnet topology (README §18.5); verify contracts on explorers.
- [ ] Seed liquidity in main pool, control pools and sibling pools; create 3 curator vaults; deposit from 2–3 test wallets.
- [ ] Recorder running across all chains (Phase 12) before the first window.
- [ ] Live windows (README §23): Thanksgiving (26 Nov), Black Friday early close (27 Nov 18:00 UTC), weekend 27–30 Nov, reconcile at Mon 30 Nov 14:30–14:45 UTC.
- [ ] Flow bot runs a scripted news event on Saturday 28 Nov (sibling + issuer move) and mixed toward/away flow.
- [ ] Export recordings to `docs/recordings/live-2026-11-26_30/`.
- **Done when:** regime callbacks for every transition, at least one news-driven anchor move with vault recenter **without a destination trade**, and one reconciliation with leaderboard update are all in explorers and in the export.

### 11.M Mainnet showcase — OUT OF SCOPE (testnet-only, ADR-011)

- [ ] 🛑 ASK USER before any step here (real funds, mainnet keys).
- [ ] Choose ticker(s) with active witnesses (from G0.1/G0.7); deploy demo tokens + NightShift on Robinhood Chain; reactive on Reactive Mainnet with real witnesses (Ethereum/BSC/Robinhood pools, issuer events if available).
- [ ] Tiny liquidity; UI + README disclaimers.
- **Done when:** at least one real-witness-driven callback on Robinhood Chain recorded.

---

## Phase 12 — Recorder and flow bot (`recorder/`)

- [ ] Event recorder (viem) per chain; resumable; SQLite/JSONL store; config from `deployments/*.json`.
- [ ] Flow bot: testnet market script (issuer price moves, sibling trades, destination toward/away mix); mainnet mode trades only our demo pools.
- [ ] Report generator: anchor vs pool tick, risk, regimes, callback latency, per-epoch results, three-pool comparison → JSON for the dashboard.
- **Done when:** `make record` and `make report` work against testnet deployments.

---

## Phase 13 — Dashboard (`app/`)

- [ ] Next.js app with wagmi/viem; reads `deployments/*.json` and report JSON.
- [ ] Pages: Live, Curators (leaderboard + deposit/withdraw/migrate), Epochs, Comparison, How it works (README §22.3).
- [ ] Explorer links for every callback (Reactscan + destination explorer).
- [ ] Deploy to Vercel (🛑 ASK USER for account).
- **Done when:** a judge can open the URL and see live state + recorded comparisons without a wallet.

---

## Phase 14 — Hardening and storytelling

- [ ] `make slither`; fix or justify every finding in `docs/security-notes.md`.
- [ ] Re-run invariants with higher runs; coverage report.
- [ ] Update README: final addresses, recordings, results table, limitations, future work (curator bonds/slashing, more witnesses, more tickers, aggregator quoting).
- [ ] `docs/pitch.md` (problem → stranded anchor → solution → proof → prior art → why Reactive → metrics → ask).
- [ ] `docs/demo-script.md` (README §23 outline) and record the ≤ 5 min video (🛑 user records/narrates).
- **Done when:** README reads as a finished project page; pitch and script ready.

---

## Phase 15 — Submission

- [ ] Repo public (🛑 ASK USER), license, README final.
- [ ] Final Submission form https://tally.so/r/mVNEAE with the **Project ID** from the idea-form email (🛑 user submits).
- [ ] Post-results: Reactive Circuit bonus claim within 14 days if placed (🛑 user).
- **Done when:** confirmation email received before **3 Dec 2026, 11:59 pm PST**.

---

## Standing checks (every phase)

- [ ] Does the change keep all 4 project criteria green? (product.md checklist)
- [ ] Does Reactive still do real, irreplaceable work, and did a callback actually fire?
- [ ] Tests added/updated; `make fmt && make test` pass.
- [ ] Steering/README/ADR updated if anything changed.
- [ ] No secrets committed.
