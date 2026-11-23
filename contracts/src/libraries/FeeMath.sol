// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolConfig, Regime} from "./Types.sol";

/// @title FeeMath
/// @notice Swap direction vs anchor, regime fee schedule, and move caps (SPEC §9.1–§9.3).
/// @dev Away pricing at the midpoint of a full allowed step (so splitting a swap is never cheaper) is adapted
///      from Gapguard (Bytethebuilder, MIT). All fees in pips (1e6 = 100%).
library FeeMath {
    /// @notice Hard fee ceiling: 10%.
    uint24 internal constant MAX_FEE = 100_000;

    /// @notice Swaps are disabled while the pool is HALTED.
    error MarketHalted();
    /// @notice An away swap moved the tick more than the allowed step.
    error AwayMoveTooLarge();
    /// @notice A toward swap crossed the anchor by more than `overshootCap`.
    error Overshoot();
    /// @notice `maxFeeClosed` exceeds `MAX_FEE`.
    error FeeCapTooHigh();

    /// @notice Revert unless the config respects hard caps.
    function validate(PoolConfig memory c) internal pure {
        if (c.maxFeeClosed > MAX_FEE) revert FeeCapTooHigh();
    }

    /// @notice Classify a swap relative to the anchor (SPEC §9.1). Inside the deadband = neutral = toward.
    /// @return away true if the swap pushes the price away from the anchor
    /// @return absD |currentTick − anchorTick|
    function direction(int24 currentTick, int24 anchorTick, bool zeroForOne, uint24 deadbandTicks)
        internal
        pure
        returns (bool away, uint256 absD)
    {
        int256 d = int256(currentTick) - int256(anchorTick);
        absD = d >= 0 ? uint256(d) : uint256(-d);
        if (absD <= deadbandTicks) return (false, absD);
        bool toward = (zeroForOne && d > 0) || (!zeroForOne && d < 0);
        away = !toward;
    }

    /// @notice LP fee for a swap (SPEC §9.2), capped at `maxFeeClosed`.
    /// @param riskUsed max(stored risk, local divergence), bps 0–10 000
    function fee(PoolConfig memory c, Regime regime, bool away, uint256 absD, uint16 riskUsed)
        internal
        pure
        returns (uint24)
    {
        uint256 f;
        if (regime == Regime.HALTED) revert MarketHalted();
        if (regime == Regime.OPEN) {
            f = away ? c.baseOpen + uint256(c.driftSlopeOpen) * absD : c.baseOpen;
        } else if (!away) {
            // toward = repair flow: CLOSED recaptures captureShare of the gap (bps of ticks -> pips: ·100/1e4)
            f = regime == Regime.CLOSED
                ? c.baseClosed + uint256(c.captureShare) * absD / 100
                : uint256(c.baseOpen) + c.reopenSurcharge;
        } else {
            uint256 drift = uint256(c.driftSlope) * (absD + c.maxAwayMove / 2);
            if (drift > c.driftMax) drift = c.driftMax;
            f = c.baseClosed + uint256(c.riskFeeMax) * riskUsed / 10_000 + drift;
        }
        return f > c.maxFeeClosed ? c.maxFeeClosed : uint24(f);
    }

    /// @notice Enforce move caps after a swap (SPEC §9.3). No-op while OPEN.
    /// @dev away: |after − before| <= maxAwayMove·(1 − risk/20 000). toward (incl. neutral): may end at most
    ///      `overshootCap` past the anchor in the swap's direction.
    function checkMove(
        PoolConfig memory c,
        Regime regime,
        bool away,
        uint16 riskUsed,
        int24 anchorTick,
        bool zeroForOne,
        int24 tickBefore,
        int24 tickAfter
    ) internal pure {
        if (regime == Regime.OPEN) return;
        if (away) {
            int256 m = int256(tickAfter) - int256(tickBefore);
            uint256 moved = m >= 0 ? uint256(m) : uint256(-m);
            if (moved * 20_000 > uint256(c.maxAwayMove) * (20_000 - uint256(riskUsed))) revert AwayMoveTooLarge();
        } else {
            int256 past = zeroForOne ? int256(anchorTick) - tickAfter : int256(tickAfter) - anchorTick;
            if (past > int256(uint256(c.overshootCap))) revert Overshoot();
        }
    }

    /// @notice Apply the away cap to the net move since the block's first swap, so splitting can't bypass it.
    /// @dev Only movement in the swap's direction counts: undoing an earlier repair in the block is not penalized.
    function checkBlockMove(
        PoolConfig memory c,
        uint16 riskUsed,
        bool zeroForOne,
        int24 blockStartTick,
        int24 tickAfter
    ) internal pure {
        int256 m = zeroForOne ? int256(blockStartTick) - tickAfter : int256(tickAfter) - blockStartTick;
        if (m > 0 && uint256(m) * 20_000 > uint256(c.maxAwayMove) * (20_000 - uint256(riskUsed))) {
            revert AwayMoveTooLarge();
        }
    }
}
