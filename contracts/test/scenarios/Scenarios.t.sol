// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

import {HookFixture} from "../utils/HookFixture.sol";
import {Regime} from "../../src/libraries/Types.sol";

/// @title Scenario replays: static 0.30% pool vs NightShift pool, identical liquidity and identical order flow
///        (SPEC §21.3). Market CLOSED all weekend; the reopen price is the witnessed fair price.
/// @notice Metrics per pool: swaps filled / blocked, LP PnL vs HODL at the reopen price (fees included, bps),
///         average fee paid (bps), |pool tick − reopen tick| at the end. Rows appended to docs/recordings/scenarios.csv
///         by `make test-scenarios`.
contract ScenariosTest is HookFixture {
    PoolKey staticKey;
    PoolId staticId;
    uint64 seq;
    int256 constant L = 1e21;

    struct Metrics {
        uint256 filled;
        uint256 blocked;
        uint256 feeSumPips;
        int256 in0;
        int256 in1;
        int256 maxGap;
    }

    int24 fairTick; // current witnessed fair price (for the premium metric)
    int24 constant RANGE = 1200; // concentrated LP (±12%)

    Metrics ns;
    Metrics st;

    function setUp() public {
        _deployHookAndPool(_satNoon()); // NightShift pool (seeded by the fixture), regime CLOSED
        vm.prank(hookOwner);
        hook.initController(address(this)); // scenarios drive the anchor directly (Reactive covered elsewhere)
        // remove the fixture seed so both pools carry exactly the same measured LP position
        modifyLiquidityRouter.modifyLiquidity(key, ModifyLiquidityParams(-12_000, 12_000, -1e22, 0), ZERO_BYTES);
        (staticKey, staticId) = initPool(currency0, currency1, IHooks(address(0)), 3000, 60, SQRT_PRICE_1_1);
        _seed(key, ns);
        _seed(staticKey, st);
    }

    // ---------------------------------------------------------------- plumbing

    function _seed(PoolKey memory k, Metrics storage m) internal {
        BalanceDelta d =
            modifyLiquidityRouter.modifyLiquidity(k, ModifyLiquidityParams(-RANGE, RANGE, L, 0), ZERO_BYTES);
        m.in0 = -int256(d.amount0());
        m.in1 = -int256(d.amount1());
    }

    function _anchor(int24 a, uint16 risk) internal {
        hook.setState(poolId, a, risk, 0, ++seq);
        fairTick = a;
    }

    function _tickOf(PoolId id) internal view returns (int24 t) {
        (, t,,) = StateLibrary.getSlot0(manager, id);
    }

    /// @dev Swap toward `target`; if blocked, the trader halves the move and retries (up to 3 times).
    function _trade(PoolKey memory k, Metrics storage m, bool isNs, int24 target, int256 maxIn) internal {
        int24 t = _tickOf(k.toId());
        int24 step = target - t;
        for (uint256 i; i < 4; i++) {
            if (_tryTrade(k, m, isNs, t + step, maxIn)) return;
            step /= 2;
            if (step == 0) return;
        }
    }

    function _tryTrade(PoolKey memory k, Metrics storage m, bool isNs, int24 target, int256 maxIn)
        internal
        returns (bool ok)
    {
        PoolId id = k.toId();
        int24 t = _tickOf(id);
        if (t == target) return true;
        bool zfo = target < t;
        uint24 feeRate = 3000;
        if (isNs) {
            try hook.quoteFee(k, zfo) returns (uint24 f, bool) {
                feeRate = f;
            } catch {}
        }
        try swapRouter.swap(
            k,
            SwapParams(zfo, -maxIn, TickMath.getSqrtPriceAtTick(target)),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        ) {
            m.filled++;
            m.feeSumPips += feeRate;
            int256 gap = _abs(int256(_tickOf(id)) - fairTick);
            if (gap > m.maxGap) m.maxGap = gap;
            ok = true;
        } catch {
            m.blocked++;
        }
    }

    /// @dev Monday open: arbitrage snaps both pools to the reopen price (against the LPs), not counted as flow.
    function _reopenArb(int24 reopenTick) internal {
        hook.setRegime(poolId, Regime.OPEN, ++seq);
        _anchor(reopenTick, 0);
        PoolKey[2] memory ks = [key, staticKey];
        for (uint256 i; i < 2; i++) {
            int24 t = _tickOf(ks[i].toId());
            if (t == reopenTick) continue;
            swapRouter.swap(
                ks[i],
                SwapParams(reopenTick < t, -1e30, TickMath.getSqrtPriceAtTick(reopenTick)),
                PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
                ZERO_BYTES
            );
        }
    }

    function _both(int24 target, int256 maxIn) internal {
        _trade(key, ns, true, target, maxIn);
        _trade(staticKey, st, false, target, maxIn);
    }

    /// @dev LP PnL vs HODL at the reopen price, fees included, in bps of the HODL value.
    function _lpPnlBps(PoolKey memory k, Metrics storage m, int24 reopenTick) internal returns (int256) {
        BalanceDelta d =
            modifyLiquidityRouter.modifyLiquidity(k, ModifyLiquidityParams(-RANGE, RANGE, -L, 0), ZERO_BYTES);
        uint160 s = TickMath.getSqrtPriceAtTick(reopenTick);
        int256 out = _val(int256(d.amount0()), int256(d.amount1()), s);
        int256 hodl = _val(m.in0, m.in1, s);
        return (out - hodl) * 10_000 / hodl;
    }

    function _val(int256 a0, int256 a1, uint160 s) internal pure returns (int256) {
        return int256(FullMath.mulDiv(FullMath.mulDiv(uint256(a0), s, 1 << 96), s, 1 << 96)) + a1;
    }

    function _report(string memory name, int24 reopenTick) internal {
        int256 gapNs = _abs(int256(_tickOf(poolId)) - reopenTick); // gap left for the reopen (before arbitrage)
        int256 gapSt = _abs(int256(_tickOf(staticId)) - reopenTick);
        _reopenArb(reopenTick);
        int256 pnlNs = _lpPnlBps(key, ns, reopenTick);
        int256 pnlSt = _lpPnlBps(staticKey, st, reopenTick);
        _row(name, "static", st, pnlSt, gapSt);
        _row(name, "nightshift", ns, pnlNs, gapNs);
    }

    function _row(string memory name, string memory pool, Metrics storage m, int256 pnl, int256 gap) internal {
        uint256 avgFeeBps = m.filled == 0 ? 0 : m.feeSumPips / m.filled / 100;
        string memory line = string.concat(
            name,
            ",",
            pool,
            ",",
            vm.toString(m.filled),
            ",",
            vm.toString(m.blocked),
            ",",
            vm.toString(pnl),
            ",",
            vm.toString(avgFeeBps),
            ",",
            vm.toString(gap),
            ",",
            vm.toString(m.maxGap)
        );
        console.log(line);
        string memory path = string.concat(vm.projectRoot(), "/../docs/recordings/scenarios.csv");
        if (vm.exists(path)) vm.writeLine(path, line);
    }

    function _abs(int256 x) internal pure returns (int256) {
        return x >= 0 ? x : -x;
    }

    // ---------------------------------------------------------------- scenarios

    /// @notice S1 quiet weekend: fair price flat, small two-way noise.
    function test_S1_quietWeekend() public {
        _anchor(0, 500);
        for (uint256 i; i < 10; i++) {
            _both(i % 2 == 0 ? int24(15) : int24(-15), 1e30);
        }
        _both(0, 1e30);
        _report("S1_quiet", 0);
    }

    /// @notice S2 news weekend: issuer + siblings reprice +4% on Saturday; arbitrage repairs the pool, then noise.
    ///         NightShift serves repair flow but recaptures 30% of the gap for LPs; static gives it away at 0.30%.
    function test_S2_newsWeekend() public {
        int24 fair = 392;
        _anchor(fair, 2000);
        for (int24 t = 50; t <= fair; t += 50) {
            _both(t, 1e30);
        }
        _both(fair, 1e30);
        for (uint256 i; i < 6; i++) {
            _both(i % 2 == 0 ? fair + 15 : fair - 15, 1e30);
        }
        _both(fair, 1e30);
        _report("S2_news", fair);
    }

    /// @notice S3 HIMS-style one-way local buying while witnesses stay flat: buyers push the price away from fair.
    ///         NightShift charges risk-scaled away fees and caps each step; static lets the premium run.
    function test_S3_oneWayLocalBuying() public {
        _anchor(0, 3000);
        for (uint256 i; i < 12; i++) {
            int24 nsTarget = _tickOf(poolId) + 150; // each buyer wants +1.5%
            int24 stTarget = _tickOf(staticId) + 150;
            _trade(key, ns, true, nsTarget, 1e30);
            _trade(staticKey, st, false, stTarget, 1e30);
        }
        _report("S3_oneway", 0);
    }

    /// @notice S5 witness outage: no fresh anchor all weekend → NightShift degrades to max protection.
    function test_S5_witnessOutage() public {
        // no _anchor(): the hook has never received a fair price → stale → every trade treated as away, risk max
        for (uint256 i; i < 10; i++) {
            int24 nsTarget = _tickOf(poolId) + (i % 2 == 0 ? int24(80) : int24(-60));
            int24 stTarget = _tickOf(staticId) + (i % 2 == 0 ? int24(80) : int24(-60));
            _trade(key, ns, true, nsTarget, 1e30);
            _trade(staticKey, st, false, stTarget, 1e30);
        }
        _report("S5_outage", 0);
    }

    /// @notice Sanity: identical seeds, so the comparison is apples to apples.
    function test_seedsIdentical() public view {
        assertEq(ns.in0, st.in0);
        assertEq(ns.in1, st.in1);
        assertEq(uint8(hook.regimeOf(poolId)), uint8(Regime.CLOSED));
    }
}
