// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title NightShift shared types
/// @notice The ONLY place shared enums/structs are declared (structure.md). SPEC §6, §7.2, §8, §9.5, §10.2, §11.

/// @notice Market regime (SPEC §6.1).
enum Regime {
    OPEN,
    CLOSED,
    REOPEN_PENDING,
    HALTED
}

/// @notice Witness source kind (SPEC §7.1).
enum SourceKind {
    ISSUER_MINT,
    ISSUER_REDEEM,
    V4_SWAP,
    V3_SWAP,
    ORACLE,
    SELF
}

/// @notice Per-pool fee policy parameters (SPEC §9.5). Fees in pips (1e6 = 100%), shares in bps, distances in ticks.
struct PoolConfig {
    uint24 baseOpen;
    uint24 baseClosed;
    uint24 driftSlopeOpen; // pips per tick of |d| for away swaps while OPEN
    uint16 captureShare; // bps of the gap recaptured from toward swaps while CLOSED
    uint24 riskFeeMax; // pips added to away fee at risk 10 000
    uint24 driftSlope; // pips per tick for away swaps while CLOSED/REOPEN_PENDING
    uint24 driftMax; // cap on the drift term
    uint24 maxFeeClosed; // global per-pool fee cap, <= MAX_FEE
    uint24 reopenSurcharge;
    uint24 deadbandTicks;
    uint24 maxAwayMove; // ticks
    uint24 overshootCap; // ticks
    uint32 anchorMaxAgeOpen; // seconds
    uint32 anchorMaxAgeClosed; // seconds
}

/// @notice Fee parameters of the Gapguard-style control pool (scenario baseline only). Pips and ticks.
struct ControlFeeParams {
    uint24 baseFee;
    uint24 closedSurcharge;
    uint24 driftCoefficient;
    uint24 maxDriftSurcharge;
    uint24 maxClosedMoveTicks;
}

/// @notice Gap Risk Score parameters (SPEC §8.1). Weights in bps, must sum to 10 000.
struct RiskParams {
    uint32 timeFullSeconds;
    uint24 dispersionFullTicks;
    uint24 divergenceFullTicks;
    uint32 stalenessFullSeconds;
    uint16 weightTime;
    uint16 weightDispersion;
    uint16 weightDivergence;
    uint16 weightStaleness;
}

/// @notice Witness source configuration (SPEC §7.2).
struct WitnessSource {
    uint256 chainId;
    address emitter;
    uint256 topic0;
    uint256 topic1;
    SourceKind kind;
    bool invert;
    int24 offsetTicks;
    uint16 weight;
    uint128 minNotional;
    uint32 maxAgeOpen;
    uint32 maxAgeClosed;
    bool enabled;
}

/// @notice Curator liquidity policy for one regime (SPEC §10.2).
struct RegimeMandate {
    uint16 followBps;
    uint24 coreHalfWidth;
    uint24 wideHalfWidth;
    uint16 coreShareBps;
    uint16 riskWidenBps;
    uint24 recenterThreshold;
    uint16 exitRiskBps;
}

/// @notice Full curator mandate (SPEC §10.2). `perfFeeBps` <= MAX_PERF_FEE (2 000).
struct Mandate {
    RegimeMandate open;
    RegimeMandate closed;
    RegimeMandate reopen;
    uint16 perfFeeBps;
}

/// @notice One vault's reconciliation result for one epoch (SPEC §11).
struct EpochResult {
    address vault;
    bytes32 poolId;
    uint64 epochId;
    int24 openTick;
    int256 alphaPerShare; // quote units per share, 1e18-scaled
    int256 cumAlpha;
    uint256 perfFeeShares;
    bool degraded;
}

/// @notice Witness-quorum, debounce and reopen parameters for NightShiftReactive (SPEC §7.4–§7.7).
struct QuorumParams {
    uint16 minQuorumWeight; // in whole weight units (scaled by WitnessMath.WEIGHT_SCALE internally)
    uint8 minDistinctChains;
    uint24 maxJumpTicks;
    uint32 halfLifeSeconds;
    uint24 minAnchorDeltaTicks;
    uint16 riskBucketBps;
    uint32 heartbeatSeconds;
    uint32 minCallbackIntervalSeconds;
    uint32 openWindowSeconds;
    uint32 reconcileTimeoutSeconds;
    uint8 issuerOpenBoost;
}

/// @notice Callback gas limits per callback type (>= 100 000 each).
struct GasLimits {
    uint64 onAnchor;
    uint64 onRegime;
    uint64 onReconcile;
}
