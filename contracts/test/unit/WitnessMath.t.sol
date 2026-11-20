// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {WitnessMath} from "../../src/libraries/WitnessMath.sol";

contract WitnessMathHarness {
    function clamp(int24 x, int24 c, uint24 j) external pure returns (int24) {
        return WitnessMath.clamp(x, c, j);
    }

    function ewma(int24 p, int24 x, uint256 dt, uint256 hl) external pure returns (int24) {
        return WitnessMath.ewma(p, x, dt, hl);
    }

    function decay(uint256 dt, uint256 hl) external pure returns (uint256) {
        return WitnessMath.decayWad(dt, hl);
    }

    function median(int24[] memory v, uint256[] memory w) external pure returns (int24) {
        return WitnessMath.weightedMedian(v, w);
    }

    function mad(int24[] memory v, uint256[] memory w, int24 c) external pure returns (uint256) {
        return WitnessMath.weightedMad(v, w, c);
    }

    function fresh(uint16 w, uint256 age, uint256 maxAge) external pure returns (uint256) {
        return WitnessMath.freshWeight(w, age, maxAge);
    }
}

contract WitnessMathTest is Test {
    WitnessMathHarness h;

    function setUp() public {
        h = new WitnessMathHarness();
    }

    // ---------- clamp (influence cap, SPEC §7.4) ----------

    function test_clamp() public view {
        assertEq(h.clamp(1000, 0, 300), 300);
        assertEq(h.clamp(-1000, 0, 300), -300);
        assertEq(h.clamp(250, 0, 300), 250);
        assertEq(h.clamp(-887_272, 887_272, 300), 886_972);
    }

    function testFuzz_clamp_withinBand(int24 x, int24 c, uint24 j) public view {
        j = uint24(bound(j, 0, 10_000));
        int24 r = h.clamp(x, c, j);
        assertLe(r >= c ? int256(r) - c : int256(c) - r, int256(uint256(j)));
        // never moves past x
        if (x >= c) assertLe(r, x);
        else assertGe(r, x);
    }

    // ---------- EWMA (SPEC §7.4) ----------

    function test_decay_points() public view {
        assertEq(h.decay(0, 300), 1e18);
        assertApproxEqRel(h.decay(300, 300), 0.5e18, 1e15); // 0.1%
        assertApproxEqRel(h.decay(600, 300), 0.25e18, 1e15);
        assertApproxEqRel(h.decay(150, 300), 0.7071067811865476e18, 1e15);
        assertEq(h.decay(300 * 300, 300), 0);
    }

    function test_ewma_halfLife_isMidpoint() public view {
        assertApproxEqAbs(h.ewma(0, 1000, 300, 300), 500, 1);
        assertEq(h.ewma(0, 1000, 0, 300), 0); // no time elapsed -> no move
        assertEq(h.ewma(0, 1000, 1 days, 300), 1000); // long gap -> converged
        assertEq(h.ewma(0, 1000, 5, 0), 1000); // halfLife 0 -> raw
    }

    function testFuzz_ewma_between(int24 p, int24 x, uint256 dt) public view {
        dt = bound(dt, 0, 30 days);
        int24 r = h.ewma(p, x, dt, 300);
        if (x >= p) {
            assertGe(r, p);
            assertLe(r, x);
        } else {
            assertLe(r, p);
            assertGe(r, x);
        }
    }

    function testFuzz_decay_monotone(uint256 a, uint256 b) public view {
        a = bound(a, 0, 1 days);
        b = bound(b, a, 1 days);
        assertGe(h.decay(a, 300), h.decay(b, 300));
    }

    // ---------- freshness weight (SPEC §7.5) ----------

    function test_freshWeight() public view {
        assertEq(h.fresh(5, 0, 600), 5 * WitnessMath.WEIGHT_SCALE);
        assertEq(h.fresh(5, 300, 600), 5 * WitnessMath.WEIGHT_SCALE / 2);
        assertEq(h.fresh(5, 600, 600), 0);
        assertEq(h.fresh(5, 900, 600), 0);
        assertEq(h.fresh(5, 0, 0), 0);
    }

    // ---------- weighted median (SPEC §7.5) ----------

    function test_median_simple() public view {
        int24[] memory v = new int24[](3);
        uint256[] memory w = new uint256[](3);
        (v[0], v[1], v[2]) = (int24(300), int24(-100), int24(100));
        (w[0], w[1], w[2]) = (uint256(1), 1, 1);
        assertEq(h.median(v, w), 100);
    }

    /// @dev Heavy issuer (5) outvotes two light siblings (2+2) that agree with each other.
    function test_median_heavyIssuerWins() public view {
        int24[] memory v = new int24[](3);
        uint256[] memory w = new uint256[](3);
        (v[0], v[1], v[2]) = (int24(400), int24(0), int24(10));
        (w[0], w[1], w[2]) = (uint256(5), 2, 2);
        assertEq(h.median(v, w), 400);
    }

    /// @dev S6: one manipulated light sibling can't move the median past honest sources.
    function test_median_ignoresSingleOutlier() public view {
        int24[] memory v = new int24[](4);
        uint256[] memory w = new uint256[](4);
        (v[0], v[1], v[2], v[3]) = (int24(100), int24(105), int24(98), int24(50_000));
        (w[0], w[1], w[2], w[3]) = (uint256(5), 3, 2, 2);
        int24 m = h.median(v, w);
        assertGe(m, 98);
        assertLe(m, 105);
    }

    function test_median_revert_noWeight() public {
        int24[] memory v = new int24[](2);
        uint256[] memory w = new uint256[](2);
        vm.expectRevert(WitnessMath.NoWeight.selector);
        h.median(v, w);
    }

    function test_median_revert_lengthMismatch() public {
        vm.expectRevert(WitnessMath.LengthMismatch.selector);
        h.median(new int24[](2), new uint256[](3));
    }

    /// @dev Brute force: lower weighted median = smallest v_i with 2·Σ{w_j : v_j <= v_i} >= Σw.
    function testFuzz_median_vsBruteForce(int24[16] memory vs, uint16[16] memory ws, uint8 n) public view {
        n = uint8(bound(n, 1, 16));
        int24[] memory v = new int24[](n);
        uint256[] memory w = new uint256[](n);
        uint256 total;
        for (uint256 i; i < n; i++) {
            v[i] = vs[i];
            w[i] = ws[i];
            total += ws[i];
        }
        if (total == 0) {
            w[0] = 1;
            total = 1;
        }
        int24 expected = type(int24).max;
        for (uint256 i; i < n; i++) {
            if (w[i] == 0) continue;
            uint256 cum;
            for (uint256 j; j < n; j++) {
                if (v[j] <= v[i]) cum += w[j];
            }
            if (2 * cum >= total && v[i] < expected) expected = v[i];
        }
        assertEq(h.median(v, w), expected);
    }

    // ---------- dispersion (weighted MAD) ----------

    function test_mad() public view {
        int24[] memory v = new int24[](3);
        uint256[] memory w = new uint256[](3);
        (v[0], v[1], v[2]) = (int24(0), int24(100), int24(-100));
        (w[0], w[1], w[2]) = (uint256(2), 1, 1);
        assertEq(h.mad(v, w, 0), 50); // (0·2 + 100 + 100) / 4
    }

    function test_mad_zeroWeight_isZero() public view {
        assertEq(h.mad(new int24[](2), new uint256[](2), 0), 0);
    }

    /// @dev Gas guard: react() is capped at 900k. Worst case (16 sources, reverse-sorted) incl. harness ABI
    ///      overhead measured ~104k; keep under 150k.
    function test_median_gas_maxSources() public view {
        int24[] memory v = new int24[](16);
        uint256[] memory w = new uint256[](16);
        for (uint256 i; i < 16; i++) {
            v[i] = int24(int256(16 - i) * 37);
            w[i] = 1 + i % 5;
        }
        uint256 g = gasleft();
        h.median(v, w);
        assertLt(g - gasleft(), 150_000);
    }
}
