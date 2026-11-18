---
inclusion: manual
---

# Decision log (ADRs)

> Template per entry: `## ADR-NNN Title` · **Date** · **Status** · **Context** · **Decision** · **Consequences**.
> Add an ADR whenever reality contradicts README/steering, or a non-obvious choice is made.

## ADR-001 Reactive Omni API is the target
- **Date:** 2026-11-18 · **Status:** Accepted
- **Context:** Reactive offers legacy RVM and the newer Omni API. README specifies Omni (`SYSTEM` callbacks, no RVM, no `Callback` event).
- **Decision:** Build against Reactive Omni: `AbstractReactive`/`AbstractCallback`, `SYSTEM 0x8888…8888`, `requestCallbackV_1_0`, first-arg identity authentication.
- **Consequences:** Exact API verified in Gate 0.3 before coding. No RVM assumptions anywhere.

## ADR-002 All prices in destination tick space
- **Date:** 2026-11-18 · **Status:** Accepted
- **Context:** Witnesses come from many chains/decimals/quote units. Comparisons and medians must be unit-free and cheap.
- **Decision:** Normalize every observation into the destination pool's tick space (1 tick ≈ 1 bp). `offsetTicks` encodes decimals/quote/multiplier, computed off-chain + unit-tested.
- **Consequences:** Median/dispersion/distance are plain tick arithmetic. Offset mistakes are the main normalization risk → test `ComputeOffsets`.

## ADR-003 Vault flows are in-kind pro-rata; vault never swaps
- **Date:** 2026-11-18 · **Status:** Accepted
- **Context:** Pricing deposits/withdrawals with a (possibly stale) anchor invites NAV games.
- **Decision:** Deposits/withdrawals in-kind pro-rata at current composition; vault never swaps; imbalance tolerated in wide/idle.
- **Consequences:** No price needed for flows → stale-NAV games impossible. Inventory can be imbalanced; acceptable.

## ADR-004 Fee semantics: toward served + gap capture, away steep + capped
- **Date:** 2026-11-18 · **Status:** Accepted
- **Context:** Idea form said "toward stays cheap". Refined: repair flow should be served (not reverted) while LPs capture part of the gap; destabilizing flow pays and is capped.
- **Decision:** Toward = served, `captureShare` (30%) of gap to LPs. Away = steep risk-scaled fee at midpoint of a full step (split never cheaper) + move cap.
- **Consequences:** Replaces the simpler "toward cheap" wording. Tuned via scenarios (ADR to follow with final params in Phase 10).

## ADR-005 Testnet topology
- **Date:** 2026-11-18 · **Status:** Accepted
- **Context:** Reactive supports Base Sepolia, Ethereum Sepolia, Unichain Sepolia, Lasna as testnets; Robinhood Chain & BSC are mainnet-only.
- **Decision:** Destination = Unichain Sepolia; origins = Ethereum Sepolia (MockIssuer + sibling A) + Base Sepolia (sibling B); reactive = Lasna.
- **Consequences:** Primary build/demo target. Mainnet (Robinhood Chain) is a stretch showcase only.

## ADR-006 Destination calendar fallback + anchor staleness (defense in depth)
- **Date:** 2026-11-18 · **Status:** Accepted
- **Context:** Reactive could be late or down; the pool must not trust stale state.
- **Decision:** Compile `NyseCalendar` into both reactive and controller; permissionless `syncRegime`/`forceReconcile`; hook stale-anchor fallback degrades to maximal (Gapguard-like) protection.
- **Consequences:** System degrades safely without Reactive, at the cost of duplicated calendar logic (kept identical).
