---
inclusion: fileMatch
fileMatchPattern: ["contracts/**/*.sol"]
---

# Solidity conventions

- **Pragma:** destination contracts `^0.8.26` (evm cancun); `NightShiftReactive` `^0.8.29` (profile `reactive`). See tech.md.
- **Custom errors**, never `require` strings. Name `PascalCase` (e.g. `NotController`, `StaleSeq`).
- **NatSpec** on every external/public function and every externally-visible error/event.
- `immutable` for deploy-time constants (proxy addresses, token refs); `constant` for literals (caps like `MAX_FEE`, `MAX_PERF_FEE`, `MAX_SOURCES`, `MAX_VAULTS_PER_POOL`).
- **Event for every state change.** No silent mutation.
- **Checks-effects-interactions**; `nonReentrant` on vault externals; external calls last.
- Use OpenZeppelin `SafeCast` for every narrowing cast (int24/uint16/uint40 packing).
- No `tx.origin`. Explicit visibility on every function and state var.
- **No unbounded loops** — cap by constant (`MAX_SOURCES = 16`, `MAX_VAULTS_PER_POOL = 8`); loops over sources/vaults bounded.
- No upgradeable proxies (SPEC §4.4).
- Format with `forge fmt`; `make fmt && make test` before every commit.
- Before coding against a library API, **read its installed source** (reactive-lib-omni, uniswap-hooks, v4-core/periphery) — names may have drifted (SPEC §13 note).
