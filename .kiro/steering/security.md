---
inclusion: fileMatch
fileMatchPattern: ["contracts/src/**"]
---

# Security model & invariants (SPEC §15)

## 🛑 ASK USER before: using private keys, any mainnet tx, spending real funds, contacting anyone.

## Threats → mitigations (§15.1)
| Threat | Mitigation |
| --- | --- |
| Forged callbacks | Controller accepts only `msg.sender == callbackProxy` AND first-arg identity `== reactive`; hook accepts only Controller |
| Replay / reordering | Monotonic `seq` per pool; `epochId` must match current epoch |
| Witness manipulation | Weighted median, per-source influence cap, EWMA, `minNotional`, ≥2 chains, issuer weight highest |
| Stale data / Reactive outage | Anchor max-age → max protection; calendar fallback `syncRegime`; `forceReconcile` |
| Curator abuse | Curator never moves funds or picks ticks; mandate bounds + timelock; perf-fee cap; HWM |
| Depositor timing games | In-kind pro-rata flows; valuation only at witnessed open tick |
| Hook DoS by failing vault | `try/catch` per vault; vault cap per pool |
| Reentrancy | `nonReentrant` on vault externals; PoolManager-only `unlockCallback` |
| Fee misconfiguration | Hard caps checked at construction/config; timelocked config |
| Stablecoin depeg (USDC vs USDT quotes) | Documented parity assumption; per-source `enabled` toggle; future stable/stable witness |
| Unscheduled closure | Timelocked override list in calendar; Reactive stale rules |

## Invariants — enforce + test (§15.2)
1. Hook state changes only via Controller; Controller only via authenticated callbacks (or permissionless fallbacks).
2. `fee ≤ maxFeeClosed ≤ MAX_FEE` always.
3. During CLOSED, stored `riskBps` non-decreasing.
4. Anchor updated only with quorum.
5. Vault: `Σ withdrawable ≤ assets held`; no function lets curator transfer tokens out.
6. Perf fee only when `cumAlpha > hwm`; `perfFeeBps ≤ 2000`.
7. `seq` strictly increasing per pool.

## Disclaimers (§15.3)
Unaudited hackathon code. Demo pools use demo tokens only. Keep any mainnet liquidity tiny and say so in UI + README. No real securities (§4.4).

## Hardening (Phase 14)
`make slither` → fix or justify every finding in `docs/security-notes.md`. Re-run invariants at higher runs; coverage report.
