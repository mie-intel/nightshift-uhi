// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BaseOverrideFee} from "@openzeppelin/uniswap-hooks/src/fee/BaseOverrideFee.sol";

import {HookFixture} from "../utils/HookFixture.sol";
import {NightShiftHook} from "../../src/hook/NightShiftHook.sol";
import {FeeMath} from "../../src/libraries/FeeMath.sol";
import {Regime} from "../../src/libraries/Types.sol";

contract NightShiftHookTest is HookFixture {
    address controller = makeAddr("controller");
    uint64 seq;

    function setUp() public {
        _deployHookAndPool(_satNoon());
        vm.prank(hookOwner);
        hook.initController(controller);
    }

    function _setAnchor(int24 anchor, uint16 risk) internal {
        vm.prank(controller);
        hook.setState(poolId, anchor, risk, 0, ++seq);
    }

    function _setRegime(Regime r) internal {
        vm.prank(controller);
        hook.setRegime(poolId, r, ++seq);
    }

    function _regime() internal view returns (Regime r) {
        (,,,, r,,,) = hook.poolState(poolId);
    }

    // ---------------------------------------------------------------- setup / permissions

    function test_permissions() public view {
        Hooks.Permissions memory p = hook.getHookPermissions();
        assertTrue(p.afterInitialize && p.beforeAddLiquidity && p.beforeSwap && p.afterSwap);
        assertFalse(p.beforeSwapReturnDelta || p.afterSwapReturnDelta || p.beforeInitialize);
    }

    function test_init_regimeFromCalendar_closedOnSaturday() public view {
        (,,,,,,, bool initialized) = hook.poolState(poolId);
        assertTrue(initialized);
        assertEq(uint8(_regime()), uint8(Regime.CLOSED));
    }

    function test_init_regimeFromCalendar_openOnMonday() public {
        vm.warp(_monOpen());
        (, PoolId id2) = initPool(currency0, currency1, IHooks(address(hook)), 0x800000, 120, SQRT_PRICE_1_1);
        (,,,, Regime r,,,) = hook.poolState(id2);
        assertEq(uint8(r), uint8(Regime.OPEN));
    }

    function test_init_revert_nonDynamicFee() public {
        vm.expectRevert(_wrapped(IHooks.afterInitialize.selector, BaseOverrideFee.NotDynamicFee.selector));
        initPool(currency0, currency1, IHooks(address(hook)), 3000, 60, SQRT_PRICE_1_1);
    }

    function test_constructor_revert_feeCapAboveMax() public {
        cfg.maxFeeClosed = FeeMath.MAX_FEE + 1;
        vm.expectRevert(FeeMath.FeeCapTooHigh.selector);
        deployCodeTo(
            "NightShiftHook.sol:NightShiftHook", abi.encode(manager, cfg, hookOwner), address(HOOK_FLAGS | (1 << 150))
        );
    }

    function test_initController_onlyOwner_once() public {
        vm.expectRevert(NightShiftHook.ControllerAlreadySet.selector);
        vm.prank(hookOwner);
        hook.initController(address(1));
        vm.expectRevert(NightShiftHook.NotOwner.selector);
        hook.initController(address(1));
    }

    // ---------------------------------------------------------------- state auth (invariants 1, 7)

    function test_setState_onlyController() public {
        vm.expectRevert(NightShiftHook.NotController.selector);
        hook.setState(poolId, 0, 0, 0, 1);
        vm.expectRevert(NightShiftHook.NotController.selector);
        hook.setRegime(poolId, Regime.OPEN, 1);
    }

    function test_setState_revert_staleSeq() public {
        _setAnchor(10, 0);
        vm.startPrank(controller);
        vm.expectRevert(NightShiftHook.StaleSeq.selector);
        hook.setState(poolId, 20, 0, 0, seq); // replay
        vm.expectRevert(NightShiftHook.StaleSeq.selector);
        hook.setRegime(poolId, Regime.OPEN, seq); // seq shared across callbacks
        vm.stopPrank();
    }

    function test_setState_revert_unknownPool() public {
        vm.prank(controller);
        vm.expectRevert(NightShiftHook.UnknownPool.selector);
        hook.setState(PoolId.wrap(bytes32(uint256(1))), 0, 0, 0, 1);
    }

    function test_setState_storesAndClampsRisk() public {
        _setAnchor(-77, 12_345);
        (int24 a, uint40 updatedAt, uint16 r,,,,,) = hook.poolState(poolId);
        assertEq(a, -77);
        assertEq(updatedAt, block.timestamp);
        assertEq(r, 10_000);
    }

    // ---------------------------------------------------------------- stale fallback (README §9.4)

    function test_noAnchor_maxProtection() public view {
        (uint24 f0, bool a0) = hook.quoteFee(key, true);
        (uint24 f1, bool a1) = hook.quoteFee(key, false);
        assertTrue(a0 && a1, "both away");
        // CLOSED away at risk 10 000, absD 0: base + riskFeeMax + driftSlope·maxAwayMove/2
        uint256 expected = cfg.baseClosed + cfg.riskFeeMax + uint256(cfg.driftSlope) * (cfg.maxAwayMove / 2);
        assertEq(f0, expected);
        assertEq(f1, expected);
    }

    function test_staleAnchor_emitsOnce_thenRecovers() public {
        _setAnchor(0, 0);
        vm.warp(block.timestamp + cfg.anchorMaxAgeClosed + 1);
        (, bool away) = hook.quoteFee(key, false);
        assertTrue(away);

        vm.expectEmit(true, false, false, false, address(hook));
        emit NightShiftHook.AnchorStale(poolId);
        _swapTo(false, 5);

        vm.recordLogs();
        _swapTo(true, 0);
        assertEq(_countTopic(NightShiftHook.AnchorStale.selector), 0, "emitted once per stale period");

        _setAnchor(0, 0);
        (, away) = hook.quoteFee(key, false);
        assertFalse(away, "fresh anchor -> neutral");
    }

    // ---------------------------------------------------------------- fees (README §9.2)

    /// @dev Pool at 0, anchor +200: buying token0 (tick up) repairs; selling pushes away.
    function test_closed_quotes_towardVsAway() public {
        _setAnchor(200, 4000);
        (uint24 tw, bool aT) = hook.quoteFee(key, false);
        (uint24 aw, bool aA) = hook.quoteFee(key, true);
        assertFalse(aT);
        assertTrue(aA);
        assertEq(tw, cfg.baseClosed + uint256(cfg.captureShare) * 200 / 100); // 0.9%
        assertEq(aw, cfg.baseClosed + uint256(cfg.riskFeeMax) * 4000 / 10_000 + uint256(cfg.driftSlope) * 250);
    }

    function test_open_baseFee() public {
        _setRegime(Regime.OPEN);
        _setAnchor(200, 0);
        (uint24 tw,) = hook.quoteFee(key, false);
        assertEq(tw, cfg.baseOpen);
    }

    // ---------------------------------------------------------------- swaps + move caps (README §9.3)

    function test_closed_bigRepairServed_upToAnchor() public {
        _setAnchor(2000, 0);
        vm.expectEmit(true, false, false, true, address(hook));
        // toward fee at a 2000-tick gap = 3000 + 60000 -> capped at maxFeeClosed
        uint256 f = cfg.baseClosed + uint256(cfg.captureShare) * 2000 / 100;
        emit NightShiftHook.SwapObserved(poolId, 0, 2000, uint24(f > cfg.maxFeeClosed ? cfg.maxFeeClosed : f), false);
        _swapTo(false, 2000);
    }

    function test_closed_overshoot_reverts() public {
        _setAnchor(0, 0); // pool at anchor: neutral swap pays toward fee, so it is bound by overshootCap
        vm.expectRevert(_wrapped(IHooks.afterSwap.selector, FeeMath.Overshoot.selector));
        _swapTo(false, int24(cfg.overshootCap) + 1);
        _swapTo(false, int24(cfg.overshootCap)); // exactly the cap: ok
    }

    function test_closed_awayMove_cappedAndShrinksWithRisk() public {
        _setAnchor(-200, 0); // pool above anchor: tick-up is away
        vm.expectRevert(_wrapped(IHooks.afterSwap.selector, FeeMath.AwayMoveTooLarge.selector));
        _swapTo(false, int24(cfg.maxAwayMove) + 1);
        _swapTo(false, int24(cfg.maxAwayMove)); // exactly the cap: ok

        _setAnchor(-200, 10_000); // max risk halves the allowed step
        vm.expectRevert(_wrapped(IHooks.afterSwap.selector, FeeMath.AwayMoveTooLarge.selector));
        _swapTo(false, int24(cfg.maxAwayMove) + int24(cfg.maxAwayMove / 2) + 1);
    }

    function test_open_noMoveCaps() public {
        _setRegime(Regime.OPEN);
        _setAnchor(-200, 0);
        _swapTo(false, 3000);
    }

    function test_halted_swapReverts() public {
        _setAnchor(0, 0);
        _setRegime(Regime.HALTED);
        vm.expectRevert(_wrapped(IHooks.beforeSwap.selector, FeeMath.MarketHalted.selector));
        _swapTo(false, 10);
    }

    /// @dev Invariant 2 on live swaps: whatever the state, the fee charged never exceeds maxFeeClosed.
    function testFuzz_swapFee_neverAboveCap(int24 anchor, uint16 risk, bool zfo) public {
        anchor = int24(bound(anchor, -5000, 5000));
        _setAnchor(anchor, risk);
        (uint24 f,) = hook.quoteFee(key, zfo);
        assertLe(f, cfg.maxFeeClosed);
        assertLe(f, FeeMath.MAX_FEE);
    }

    // ---------------------------------------------------------------- helpers

    function _countTopic(bytes32 topic) internal view returns (uint256 n) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) n++;
        }
    }
}
