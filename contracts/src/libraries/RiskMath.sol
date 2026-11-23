// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Regime, RiskParams} from "./Types.sol";

/// @title RiskMath
/// @notice Gap Risk Score components and the closed-market ratchet (SPEC §8).
/// @dev The idea of a Reactive-fed risk score that only ratchets up and feeds the swap fee is credited to Veritas (UHI9).
library RiskMath {
    uint256 private constant BPS = 10_000;

    /// @notice Weights don't sum to 10 000 or a full-scale value is zero.
    error BadRiskParams();

    /// @notice Revert unless weights sum to 10 000 and every full-scale value is non-zero.
    function validate(RiskParams memory p) internal pure {
        uint256 sum = uint256(p.weightTime) + p.weightDispersion + p.weightDivergence + p.weightStaleness;
        if (
            sum != BPS || p.timeFullSeconds == 0 || p.dispersionFullTicks == 0 || p.divergenceFullTicks == 0
                || p.stalenessFullSeconds == 0
        ) revert BadRiskParams();
    }

    /// @notice min(1, value/full) in bps.
    function component(uint256 value, uint256 full) internal pure returns (uint256) {
        if (value >= full) return BPS;
        return value * BPS / full;
    }

    /// @notice Raw risk = Σ weight_i · component_i, bps 0–10 000 (SPEC §8.1). Assumes `validate(p)` passed.
    /// @param sinceOpenAnchor seconds since the last open-market anchor (reconcile)
    /// @param dispersionTicks weighted MAD of fresh witnesses
    /// @param divergenceTicks |selfTick − anchor|
    /// @param sinceQuorum seconds since quorum was last reached
    function raw(
        RiskParams memory p,
        uint256 sinceOpenAnchor,
        uint256 dispersionTicks,
        uint256 divergenceTicks,
        uint256 sinceQuorum
    ) internal pure returns (uint16) {
        uint256 r = p.weightTime * component(sinceOpenAnchor, p.timeFullSeconds) + p.weightDispersion
            * component(dispersionTicks, p.dispersionFullTicks) + p.weightDivergence
            * component(divergenceTicks, p.divergenceFullTicks) + p.weightStaleness
            * component(sinceQuorum, p.stalenessFullSeconds);
        return uint16(r / BPS);
    }

    /// @notice Next stored risk (SPEC §8.2). OPEN: raw. Any other regime: max(prev, raw) — risk only ratchets up
    ///         until reconciliation resets it to 0 (REOPEN_PENDING/HALTED keep the closed-epoch ratchet).
    function next(Regime regime, uint16 prev, uint16 rawRisk) internal pure returns (uint16) {
        if (regime == Regime.OPEN) return rawRisk;
        return rawRisk > prev ? rawRisk : prev;
    }
}
