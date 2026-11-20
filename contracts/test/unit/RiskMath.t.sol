// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {RiskMath} from "../../src/libraries/RiskMath.sol";
import {Regime, RiskParams} from "../../src/libraries/Types.sol";

contract RiskMathHarness {
    function validate(RiskParams memory p) external pure {
        RiskMath.validate(p);
    }

    function component(uint256 v, uint256 full) external pure returns (uint256) {
        return RiskMath.component(v, full);
    }

    function raw(RiskParams memory p, uint256 t, uint256 disp, uint256 div, uint256 stale)
        external
        pure
        returns (uint16)
    {
        return RiskMath.raw(p, t, disp, div, stale);
    }

    function next(Regime r, uint16 prev, uint16 rawRisk) external pure returns (uint16) {
        return RiskMath.next(r, prev, rawRisk);
    }
}

contract RiskMathTest is Test {
    RiskMathHarness h;
    RiskParams p;

    function setUp() public {
        h = new RiskMathHarness();
        // SPEC §8.1 defaults (= contracts/config/testnet.json "risk")
        p = RiskParams({
            timeFullSeconds: 64 hours,
            dispersionFullTicks: 200,
            divergenceFullTicks: 300,
            stalenessFullSeconds: 4 hours,
            weightTime: 3000,
            weightDispersion: 2500,
            weightDivergence: 3000,
            weightStaleness: 1500
        });
    }

    function test_validate_ok() public view {
        h.validate(p);
    }

    function test_validate_revert_weightsNot10000() public {
        p.weightTime = 2999;
        vm.expectRevert(RiskMath.BadRiskParams.selector);
        h.validate(p);
    }

    function test_validate_revert_zeroFullScale() public {
        p.dispersionFullTicks = 0;
        vm.expectRevert(RiskMath.BadRiskParams.selector);
        h.validate(p);
    }

    function test_component() public view {
        assertEq(h.component(0, 200), 0);
        assertEq(h.component(100, 200), 5000);
        assertEq(h.component(200, 200), 10_000);
        assertEq(h.component(10_000, 200), 10_000);
    }

    function test_raw_zero() public view {
        assertEq(h.raw(p, 0, 0, 0, 0), 0);
    }

    function test_raw_full() public view {
        assertEq(h.raw(p, 64 hours, 200, 300, 4 hours), 10_000);
        assertEq(h.raw(p, 1000 hours, 1e6, 1e6, 1000 hours), 10_000);
    }

    /// @dev Friday close -> Saturday noon: 15h of 64h time, quiet witnesses.
    function test_raw_weekendExample() public view {
        // components floor first: time 15/64 -> 2343 bps, dispersion 1000, divergence 1000, staleness 0
        // (3000·2343 + 2500·1000 + 3000·1000) / 1e4 = 1252.9 -> 1252
        assertEq(h.raw(p, 15 hours, 20, 30, 0), 1252);
    }

    function test_next_openFollowsRaw() public view {
        assertEq(h.next(Regime.OPEN, 9000, 100), 100);
    }

    function test_next_closedRatchets() public view {
        assertEq(h.next(Regime.CLOSED, 4000, 100), 4000);
        assertEq(h.next(Regime.CLOSED, 4000, 4100), 4100);
        assertEq(h.next(Regime.REOPEN_PENDING, 4000, 100), 4000);
        assertEq(h.next(Regime.HALTED, 4000, 100), 4000);
    }

    function testFuzz_raw_bounded(uint32 t, uint24 d, uint24 v, uint32 s) public view {
        assertLe(h.raw(p, t, d, v, s), 10_000);
    }

    /// @dev Invariant 3: during CLOSED stored risk is non-decreasing for any sequence of raw inputs.
    function testFuzz_closed_ratchetMonotonic(uint16[8] memory raws, uint16 start) public view {
        uint16 r = uint16(bound(start, 0, 10_000));
        for (uint256 i; i < raws.length; i++) {
            uint16 nr = h.next(Regime.CLOSED, r, uint16(bound(raws[i], 0, 10_000)));
            assertGe(nr, r);
            r = nr;
        }
    }

    function testFuzz_raw_monotoneInEachInput(uint32 t, uint24 d, uint24 v, uint32 s, uint32 bump) public view {
        uint16 base = h.raw(p, t, d, v, s);
        assertGe(h.raw(p, uint256(t) + bump, d, v, s), base);
        assertGe(h.raw(p, t, uint256(d) + bump, v, s), base);
        assertGe(h.raw(p, t, d, uint256(v) + bump, s), base);
        assertGe(h.raw(p, t, d, v, uint256(s) + bump), base);
    }
}
