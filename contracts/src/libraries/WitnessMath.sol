// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title WitnessMath
/// @notice Influence cap, time-weighted EWMA, freshness weight, weighted median and weighted MAD (README §7.4–§7.5).
/// @dev All values in destination ticks. Kept lean: runs inside react() (900k gas cap).
library WitnessMath {
    /// @notice Fixed-point scale for effective (freshness-decayed) weights.
    uint256 internal constant WEIGHT_SCALE = 1e4;
    uint256 private constant WAD = 1e18;
    uint256 private constant LN2_WAD = 693_147_180_559_945_309;

    /// @notice Weighted median/MAD called with all-zero weights.
    error NoWeight();
    /// @notice Value and weight arrays differ in length.
    error LengthMismatch();

    /// @notice Clamp `x` into `[center − j, center + j]` (per-source influence cap).
    function clamp(int24 x, int24 center, uint24 j) internal pure returns (int24) {
        int256 lo = int256(center) - int256(uint256(j));
        int256 hi = int256(center) + int256(uint256(j));
        if (x < lo) return int24(lo);
        if (x > hi) return int24(hi);
        return x;
    }

    /// @notice 2^(−dt/halfLife) in WAD. Integer halvings by shift; fractional part via 5th-order e^(−x) Taylor
    ///         (abs error < 2e-4).
    function decayWad(uint256 dt, uint256 halfLife) internal pure returns (uint256) {
        if (halfLife == 0) return 0;
        uint256 n = dt / halfLife;
        if (n >= 60) return 0;
        uint256 x = (dt % halfLife) * LN2_WAD / halfLife; // in [0, ln2)
        uint256 x2 = x * x / WAD;
        uint256 x3 = x2 * x / WAD;
        uint256 x4 = x3 * x / WAD;
        uint256 x5 = x4 * x / WAD;
        uint256 e = WAD + x2 / 2 + x4 / 24 - x - x3 / 6 - x5 / 120;
        return e >> n;
    }

    /// @notice Time-weighted EWMA step: prev + α·(x − prev), α = 1 − 2^(−dt/halfLife). Result lies between prev and x.
    function ewma(int24 prev, int24 x, uint256 dt, uint256 halfLife) internal pure returns (int24) {
        uint256 alpha = WAD - decayWad(dt, halfLife);
        int256 diff = int256(x) - int256(prev);
        return int24(int256(prev) + diff * int256(alpha) / int256(WAD));
    }

    /// @notice Effective weight `weight·(1 − age/maxAge)` scaled by WEIGHT_SCALE; 0 once stale.
    function freshWeight(uint16 weight, uint256 age, uint256 maxAge) internal pure returns (uint256) {
        if (age >= maxAge) return 0;
        return uint256(weight) * WEIGHT_SCALE * (maxAge - age) / maxAge;
    }

    /// @notice Lower weighted median: smallest v with 2·Σ{w : value <= v} >= Σw.
    /// @dev Sorts `values`/`weights` IN PLACE (insertion sort; n <= MAX_SOURCES).
    function weightedMedian(int24[] memory values, uint256[] memory weights) internal pure returns (int24) {
        uint256 n = values.length;
        if (weights.length != n) revert LengthMismatch();
        uint256 total;
        for (uint256 i = 1; i < n; ++i) {
            int24 v = values[i];
            uint256 w = weights[i];
            uint256 j = i;
            while (j > 0 && values[j - 1] > v) {
                values[j] = values[j - 1];
                weights[j] = weights[j - 1];
                --j;
            }
            values[j] = v;
            weights[j] = w;
        }
        for (uint256 i; i < n; ++i) {
            total += weights[i];
        }
        if (total == 0) revert NoWeight();
        uint256 cum;
        for (uint256 i; i < n; ++i) {
            cum += weights[i];
            if (2 * cum >= total) return values[i];
        }
        return values[n - 1]; // unreachable
    }

    /// @notice Weighted mean absolute deviation from `center`, in ticks (dispersion). 0 if no weight.
    function weightedMad(int24[] memory values, uint256[] memory weights, int24 center)
        internal
        pure
        returns (uint256)
    {
        if (weights.length != values.length) revert LengthMismatch();
        uint256 total;
        uint256 acc;
        for (uint256 i; i < values.length; ++i) {
            int256 d = int256(values[i]) - center;
            acc += weights[i] * (d >= 0 ? uint256(d) : uint256(-d));
            total += weights[i];
        }
        return total == 0 ? 0 : acc / total;
    }
}
