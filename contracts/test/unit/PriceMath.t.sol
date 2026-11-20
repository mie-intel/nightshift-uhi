// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {PriceMath} from "../../src/libraries/PriceMath.sol";

contract PriceMathHarness {
    function tickFromRatio(uint256 quote, uint256 base) external pure returns (int24) {
        return PriceMath.tickFromRatio(quote, base);
    }

    function normalize(int24 t, bool inv, int24 off) external pure returns (int24) {
        return PriceMath.normalize(t, inv, off);
    }
}

contract PriceMathTest is Test {
    PriceMathHarness h;

    function setUp() public {
        h = new PriceMathHarness();
    }

    /// @dev Tick t must bracket the ratio: sqrtP(t) <= sqrt(ratio) < sqrtP(t+1)  (floor semantics).
    function _assertBrackets(uint256 quote, uint256 base, int24 t) internal pure {
        uint256 lo = TickMath.getSqrtPriceAtTick(t);
        uint256 hi = TickMath.getSqrtPriceAtTick(t + 1);
        // price(t) = lo^2 / 2^192 ; compare against quote/base without overflow via mulDiv
        uint256 pLoX128 = FullMath.mulDiv(lo, lo, 1 << 64);
        uint256 pHiX128 = FullMath.mulDiv(hi, hi, 1 << 64);
        uint256 rX128 = FullMath.mulDiv(quote, 1 << 128, base);
        // floor semantics up to rounding: ratios within 1e-8 of a tick boundary may land on either side (spec ±1 tick)
        assertLe(pLoX128, rX128 + rX128 / 1e8 + 1, "tick above ratio");
        assertGt(pHiX128 + pHiX128 / 1e8 + 1, rX128, "tick below ratio");
    }

    function test_ratioOne_isTickZero() public view {
        assertEq(h.tickFromRatio(1e18, 1e18), 0);
    }

    /// @dev Exactly on a tick boundary, floor rounding may land one tick below (spec: within 1 tick).
    function test_ratio_1p0001pow100_isTick100() public view {
        uint256 q = uint256(TickMath.getSqrtPriceAtTick(100));
        int24 t = h.tickFromRatio(FullMath.mulDiv(q, q, 1 << 96), 1 << 96);
        assertApproxEqAbs(int256(t), 100, 1);
        // just above the boundary resolves exactly
        uint256 r = FullMath.mulDiv(q, q, 1 << 96);
        assertEq(h.tickFromRatio(r + r / 1e12, 1 << 96), 100);
    }

    /// @dev dSTOCK (18 dec) priced at 100 dUSD (6 dec): raw ratio = 100e6 / 1e18 = 1e-10.
    function test_decimals_dStockAt100dUsd() public view {
        int24 t = h.tickFromRatio(100e6, 1e18);
        _assertBrackets(100e6, 1e18, t);
        assertApproxEqAbs(int256(t), -230271, 1);
    }

    function test_priceAbove1_positiveTick() public view {
        int24 t = h.tickFromRatio(4e18, 1e18); // ln4/ln1.0001 ~ 13863
        _assertBrackets(4e18, 1e18, t);
        assertApproxEqAbs(int256(t), 13863, 1);
    }

    /// @dev Regression (fuzz found, 20 Nov 2026): tiny ratios lost precision via the X128 path (tick off by ≥1).
    function test_regression_tinyRatio_precision() public view {
        uint256 q = 3067;
        uint256 b = 79_228_162_514_264_337_593_543_949_487;
        int24 t = h.tickFromRatio(q, b);
        _assertBrackets(q, b, t);
    }

    function test_inversion_isNegation() public view {
        int24 a = h.tickFromRatio(4e18, 1e18);
        int24 b = h.tickFromRatio(1e18, 4e18);
        assertApproxEqAbs(int256(a), -int256(b), 1);
    }

    function test_revert_zeroAmount() public {
        vm.expectRevert(PriceMath.ZeroAmount.selector);
        h.tickFromRatio(0, 1);
        vm.expectRevert(PriceMath.ZeroAmount.selector);
        h.tickFromRatio(1, 0);
    }

    function test_extremeRatios_clampToTickBounds() public view {
        assertEq(h.tickFromRatio(1, type(uint128).max), TickMath.MIN_TICK);
        assertEq(h.tickFromRatio(type(uint128).max, 1), TickMath.MAX_TICK - 1);
    }

    function test_normalize() public view {
        assertEq(h.normalize(100, false, 5), 105);
        assertEq(h.normalize(100, true, 5), -95);
        assertEq(h.normalize(TickMath.MAX_TICK, false, 10), TickMath.MAX_TICK);
        assertEq(h.normalize(TickMath.MIN_TICK, false, -10), TickMath.MIN_TICK);
    }

    /// @dev Round trip: tick -> exact ratio -> tick within 1.
    function testFuzz_roundTrip(int24 t) public view {
        t = int24(bound(t, -400_000, 400_000));
        uint256 s = TickMath.getSqrtPriceAtTick(t);
        uint256 quote = FullMath.mulDiv(s, s, 1 << 96);
        int24 got = h.tickFromRatio(quote, 1 << 96);
        assertApproxEqAbs(int256(got), int256(t), 1);
    }

    /// @dev Floor semantics hold for arbitrary realistic mint amounts.
    function testFuzz_brackets(uint96 quote, uint96 base) public view {
        quote = uint96(bound(quote, 1e3, type(uint96).max));
        base = uint96(bound(base, 1e3, type(uint96).max));
        int24 t = h.tickFromRatio(quote, base);
        _assertBrackets(quote, base, t);
    }
}
