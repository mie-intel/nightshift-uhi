// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FeeMath} from "../../src/libraries/FeeMath.sol";
import {PoolConfig, Regime} from "../../src/libraries/Types.sol";

contract FeeMathHarness {
    function validate(PoolConfig memory c) external pure {
        FeeMath.validate(c);
    }

    function direction(int24 cur, int24 anchor, bool zfo, uint24 db) external pure returns (bool, uint256) {
        return FeeMath.direction(cur, anchor, zfo, db);
    }

    function fee(PoolConfig memory c, Regime r, bool away, uint256 absD, uint16 risk) external pure returns (uint24) {
        return FeeMath.fee(c, r, away, absD, risk);
    }

    function checkMove(
        PoolConfig memory c,
        Regime r,
        bool away,
        uint16 risk,
        int24 anchor,
        bool zfo,
        int24 before_,
        int24 after_
    ) external pure {
        FeeMath.checkMove(c, r, away, risk, anchor, zfo, before_, after_);
    }
}

contract FeeMathTest is Test {
    FeeMathHarness h;
    PoolConfig c;

    function setUp() public {
        h = new FeeMathHarness();
        // README §9.5 defaults (= contracts/config/testnet.json "fee")
        c = PoolConfig({
            baseOpen: 3000,
            baseClosed: 3000,
            driftSlopeOpen: 2,
            captureShare: 3000,
            riskFeeMax: 10_000,
            driftSlope: 20,
            driftMax: 45_000,
            maxFeeClosed: 50_000,
            reopenSurcharge: 1000,
            deadbandTicks: 5,
            maxAwayMove: 100,
            overshootCap: 20,
            anchorMaxAgeOpen: 1800,
            anchorMaxAgeClosed: 21_600
        });
    }

    // ---------- validate ----------

    function test_validate_ok() public view {
        h.validate(c);
    }

    function test_validate_revert_capAboveMaxFee() public {
        c.maxFeeClosed = FeeMath.MAX_FEE + 1;
        vm.expectRevert(FeeMath.FeeCapTooHigh.selector);
        h.validate(c);
    }

    // ---------- direction (README §9.1) ----------

    function test_direction_table() public view {
        bool away;
        uint256 d;
        // pool above anchor (d = +50): selling token0 (zeroForOne, tick down) is toward
        (away, d) = h.direction(150, 100, true, 5);
        assertFalse(away);
        assertEq(d, 50);
        (away,) = h.direction(150, 100, false, 5);
        assertTrue(away);
        // pool below anchor (d = -50)
        (away, d) = h.direction(50, 100, false, 5);
        assertFalse(away);
        assertEq(d, 50);
        (away,) = h.direction(50, 100, true, 5);
        assertTrue(away);
        // inside deadband -> neutral (toward), both directions
        (away,) = h.direction(104, 100, false, 5);
        assertFalse(away);
        (away,) = h.direction(96, 100, true, 5);
        assertFalse(away);
        (away,) = h.direction(105, 100, false, 5); // |d| == deadband still neutral
        assertFalse(away);
        (away,) = h.direction(106, 100, false, 5);
        assertTrue(away);
    }

    // ---------- fee schedule (README §9.2) ----------

    function test_fee_open() public view {
        assertEq(h.fee(c, Regime.OPEN, false, 200, 0), 3000);
        assertEq(h.fee(c, Regime.OPEN, true, 200, 0), 3000 + 2 * 200);
    }

    /// @dev 200-tick gap, captureShare 30% -> +60 bp = 6000 pips on top of base.
    function test_fee_closed_toward_capturesGap() public view {
        assertEq(h.fee(c, Regime.CLOSED, false, 200, 0), 3000 + 6000);
        assertEq(h.fee(c, Regime.CLOSED, false, 0, 9000), 3000); // risk does not tax repair flow
    }

    function test_fee_closed_away() public view {
        // base + riskFeeMax*risk/1e4 + min(driftMax, driftSlope*(d + maxAwayMove/2))
        assertEq(h.fee(c, Regime.CLOSED, true, 0, 0), 3000 + 0 + 20 * 50);
        assertEq(h.fee(c, Regime.CLOSED, true, 100, 5000), 3000 + 5000 + 20 * 150);
    }

    function test_fee_closed_away_driftCapped_thenGlobalCap() public view {
        // drift term capped at driftMax: 3000 + 10000 + 45000 = 58000 > maxFeeClosed -> 50000
        assertEq(h.fee(c, Regime.CLOSED, true, 100_000, 10_000), 50_000);
    }

    function test_fee_reopen() public view {
        assertEq(h.fee(c, Regime.REOPEN_PENDING, false, 300, 0), 3000 + 1000);
        assertEq(h.fee(c, Regime.REOPEN_PENDING, true, 0, 0), h.fee(c, Regime.CLOSED, true, 0, 0));
    }

    function test_fee_halted_reverts() public {
        vm.expectRevert(FeeMath.MarketHalted.selector);
        h.fee(c, Regime.HALTED, false, 0, 0);
    }

    function testFuzz_fee_neverAboveCap(uint8 r, bool away, uint256 absD, uint16 risk) public view {
        Regime reg = Regime(bound(r, 0, 2));
        absD = bound(absD, 0, 2 * 887_272);
        risk = uint16(bound(risk, 0, 10_000));
        uint24 f = h.fee(c, reg, away, absD, risk);
        assertLe(f, c.maxFeeClosed);
        assertLe(f, FeeMath.MAX_FEE);
    }

    /// @dev Splitting an away swap is never cheaper: each later chunk starts further from the anchor
    ///      (larger |d|) under a non-decreasing risk, so its fee rate is >= the first chunk's.
    function testFuzz_away_splitNeverCheaper(uint256 d1, uint256 step, uint16 r1, uint16 rUp) public view {
        d1 = bound(d1, 0, 500_000);
        step = bound(step, 0, 500_000);
        r1 = uint16(bound(r1, 0, 10_000));
        uint16 r2 = uint16(bound(uint256(r1) + rUp, r1, 10_000));
        assertGe(h.fee(c, Regime.CLOSED, true, d1 + step, r2), h.fee(c, Regime.CLOSED, true, d1, r1));
    }

    /// @dev Away always costs at least as much as toward at the same distance (rate-wise, CLOSED, risk 0)
    ///      for distances inside the allowed step.
    function testFuzz_away_geToward_withinStep(uint256 d) public view {
        d = bound(d, 0, c.maxAwayMove);
        assertGe(h.fee(c, Regime.CLOSED, true, d, 0), h.fee(c, Regime.OPEN, false, d, 0));
    }

    // ---------- move caps (README §9.3) ----------

    function test_awayMove_withinCap_ok() public view {
        h.checkMove(c, Regime.CLOSED, true, 0, 0, false, 0, 100);
    }

    function test_awayMove_tooLarge_reverts() public {
        vm.expectRevert(FeeMath.AwayMoveTooLarge.selector);
        h.checkMove(c, Regime.CLOSED, true, 0, 0, false, 0, 101);
    }

    /// @dev At risk 10 000 the allowed away step halves (100 -> 50).
    function test_awayMove_capShrinksWithRisk() public {
        h.checkMove(c, Regime.CLOSED, true, 10_000, 0, true, 0, -50);
        vm.expectRevert(FeeMath.AwayMoveTooLarge.selector);
        h.checkMove(c, Regime.CLOSED, true, 10_000, 0, true, 0, -51);
    }

    function test_awayMove_notCappedWhenOpen() public view {
        h.checkMove(c, Regime.OPEN, true, 0, 0, false, 0, 10_000);
    }

    /// @dev Large toward swap served in full up to anchor + overshootCap.
    function test_toward_bigRepairServed() public view {
        // pool at +2000 above anchor 0, sells down to -20 (exactly overshootCap past anchor)
        h.checkMove(c, Regime.CLOSED, false, 0, 0, true, 2000, -20);
    }

    function test_toward_overshoot_reverts() public {
        vm.expectRevert(FeeMath.Overshoot.selector);
        h.checkMove(c, Regime.CLOSED, false, 0, 0, true, 2000, -21);
        vm.expectRevert(FeeMath.Overshoot.selector);
        h.checkMove(c, Regime.REOPEN_PENDING, false, 0, 0, false, -2000, 21);
    }

    function test_toward_overshootIgnoredWhenOpen() public view {
        h.checkMove(c, Regime.OPEN, false, 0, 0, true, 2000, -5000);
    }
}
