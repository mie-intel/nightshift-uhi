---
inclusion: always
---

# NightShift — repo structure & conventions

## Tree (README §17)

```
nightshift/
├── CLAUDE.md              # Claude Code entry → imports Kiro steering
├── README.md              # spec (single source of truth; cite § numbers)
├── TODO.md                # plan (phase order + done criteria)
├── Makefile · .env.example · .gitignore · LICENSE
├── .kiro/steering/        # product, tech, structure, glossary (always);
│                          # decisions, hookathon (manual); scoped fileMatch files
├── .claude/rules/         # thin bridges: paths: frontmatter + @import of the Kiro file
├── contracts/
│   ├── foundry.toml · remappings.txt
│   ├── config/{testnet,mainnet}.json   # all tunable params
│   ├── src/
│   │   ├── hook/NightShiftHook.sol
│   │   ├── controller/NightShiftController.sol
│   │   ├── vault/{NightShiftVault,VaultFactory}.sol
│   │   ├── registry/CuratorRegistry.sol
│   │   ├── reactive/NightShiftReactive.sol
│   │   ├── libraries/{NyseCalendar,PriceMath,WitnessMath,RiskMath,FeeMath,Types}.sol
│   │   ├── interfaces/{INightShiftHook,INightShiftController,INightShiftVault,ICuratorRegistry}.sol
│   │   └── mocks/{DemoToken,MockIssuer,ControlClosedSurchargeHook,MockSystemContract}.sol
│   ├── script/            # 00_DeployTokens … 05_CreateCuratorVaults, ComputeOffsets
│   └── test/{unit,fuzz,invariant,integration,scenarios}/
├── recorder/              # TS: event recorder, flow bot, report generator
├── app/                   # Next.js dashboard
├── deployments/{testnet,mainnet}.json
└── docs/{architecture,demo-script,pitch}.md · docs/recordings/
```

## Where each contract lives and what it owns

- **Hook** (`src/hook/`): dynamic fee per swap, move caps, stale-anchor fallback, `curatedOnly` gate, per-`PoolId` state. Owns nothing but its pool state; state set only by Controller.
- **Controller** (`src/controller/`): the callback receiver (`AbstractCallback`). Authenticates callbacks, fans out to hook + vaults, holds permissionless fallbacks (`syncRegime`, `forceReconcile`).
- **Reactive** (`src/reactive/`): the only contract on Reactive Network. Witness quorum, risk, regime, reconcile, corporate actions; requests callbacks.
- **Vault + Factory** (`src/vault/`): per-curator liquidity, in-kind flows, rebalance, snapshot/reconcile. Never swaps, never holds others' funds beyond shares.
- **Registry** (`src/registry/`): pool registration, timelocked `PoolConfig`, vault registry, leaderboard, `migrate`.
- **Libraries** (`src/libraries/`): pure math/calendar. Shared structs/enums live ONLY in `Types.sol`.
- **Mocks** (`src/mocks/`): testnet-only `DemoToken`, `MockIssuer`, `ControlClosedSurchargeHook` (Gapguard-style, credited), `MockSystemContract` (local harness).

## Naming conventions

- Contracts & libraries: `PascalCase`. Interfaces: `IName` in `src/interfaces/`.
- Tests: `Contract.t.sol`. Scenarios: `Scenario_SN_Name.t.sol` (e.g. `Scenario_S1_NormalWeekend.t.sol`).
- Scripts: numbered `NN_Name.s.sol`; helpers unnumbered (`ComputeOffsets.s.sol`).
- Custom errors `PascalCase`; events `PascalCase`.

## Import patterns

- Remapping aliases (README §16): `@uniswap/v4-core/`, `@uniswap/v4-periphery/`, `@openzeppelin/uniswap-hooks/`, `@openzeppelin/contracts/`, `@reactive/`, `forge-std/`.
- Interfaces always in `src/interfaces/`; contracts depend on interfaces, not each other, where possible.
- Shared structs/enums ONLY in `libraries/Types.sol` — never redeclared.

## Config & deployments layout

- `contracts/config/{testnet,mainnet}.json`: pool params (§9.5), quorum (§7), risk (§8), mandate presets (§10). Read by scripts with `vm.readFile` + `stdJson`. `fs_permissions` in `foundry.toml` must allow `config/` and `../deployments/`.
- `deployments/{network}.json`: written by scripts; addresses consumed by recorder + app.

## Docs layout

`docs/architecture.md`, `docs/demo-script.md`, `docs/pitch.md`, `docs/security-notes.md` (Phase 14), `docs/verification.md` (Gate 0), `docs/recordings/` (CSV/JSON + e2e.md link logs + live exports).
