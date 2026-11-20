// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title PriceMath
/// @notice Ratio -> tick conversion and source normalization into destination tick space (SPEC §7.3).
library PriceMath {
    /// @notice A ratio input was zero.
    error ZeroAmount();

    /// @notice Tick of the raw ratio `quote / base` (token1 per token0, raw units), floored like TickMath.
    /// @dev ratio < 2^64: sqrtPriceX96 = sqrt(quote·2^192/base) (full precision even for tiny ratios).
    ///      ratio ≥ 2^64: sqrt(quote·2^128/base) << 32 (the X192 product would overflow; precision is ample there).
    ///      Clamped to TickMath bounds.
    /// @param quote quote-token amount (raw units)
    /// @param base base-token amount (raw units)
    function tickFromRatio(uint256 quote, uint256 base) internal pure returns (int24) {
        if (quote == 0 || base == 0) revert ZeroAmount();
        // ratio must stay < 2^128 for mulDiv; anything above is beyond MAX_TICK anyway.
        if (quote / base >= type(uint128).max) return TickMath.MAX_TICK - 1;
        uint256 sqrtX96 = quote / base < (1 << 64)
            ? Math.sqrt(FullMath.mulDiv(quote, 1 << 192, base))
            : Math.sqrt(FullMath.mulDiv(quote, 1 << 128, base)) << 32;
        if (sqrtX96 < TickMath.MIN_SQRT_PRICE) return TickMath.MIN_TICK;
        if (sqrtX96 >= TickMath.MAX_SQRT_PRICE) return TickMath.MAX_TICK - 1;
        return TickMath.getTickAtSqrtPrice(uint160(sqrtX96));
    }

    /// @notice Map a source tick into destination tick space: `(invert ? -t : t) + offset`, clamped to tick bounds.
    function normalize(int24 srcTick, bool invert, int24 offsetTicks) internal pure returns (int24) {
        int256 t = (invert ? -int256(srcTick) : int256(srcTick)) + offsetTicks;
        if (t > TickMath.MAX_TICK) return TickMath.MAX_TICK;
        if (t < TickMath.MIN_TICK) return TickMath.MIN_TICK;
        return int24(t);
    }
}
