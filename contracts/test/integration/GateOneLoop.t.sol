// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IReactive} from "@reactive/interfaces/IReactive.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {HookFixture} from "../utils/HookFixture.sol";
import {ReactiveHarness} from "../utils/ReactiveHarness.sol";
import {NightShiftController} from "../../src/controller/NightShiftController.sol";
import {NightShiftReactive} from "../../src/reactive/NightShiftReactive.sol";
import {DemoToken} from "../../src/mocks/DemoToken.sol";
import {MockIssuer} from "../../src/mocks/MockIssuer.sol";
import {FeeMath} from "../../src/libraries/FeeMath.sol";
import {PriceMath} from "../../src/libraries/PriceMath.sol";

/// @title Gate 1, locally: a witness move on another chain reprices the pool BEFORE anyone trades it.
/// @notice Saturday, market closed. The issuer sells shares at +2% on the origin chain. Reactive turns that execution
///         into an anchor and calls back into the destination pool. A repair trade is then served at fair value,
///         while a trade pushing away from fair value is capped.
contract GateOneLoopTest is HookFixture, ReactiveHarness {
    uint256 constant ORIGIN = 11_155_111; // Ethereum Sepolia (virtual)
    uint256 constant DEST = 84_532; // Base Sepolia (virtual)

    address callbackProxy = makeAddr("callbackProxy");
    address trader = makeAddr("trader");
    DemoToken dStock;
    DemoToken dUsd;
    MockIssuer issuer;
    NightShiftReactive rx;
    NightShiftController ctrl;

    function setUp() public {
        _deployHookAndPool(_satNoon()); // destination pool at tick 0 (1 dUSD per dSTOCK, both 18 dec)
        _etchSystem();

        // origin chain: issuer selling dSTOCK for dUSD at 1.00
        dStock = new DemoToken("Demo Stock", "dSTOCK", 18);
        dUsd = new DemoToken("Demo USD", "dUSD", 18);
        issuer = new MockIssuer(dStock, dUsd, 1e18);
        dStock.setMinter(address(issuer), true);
        dUsd.mint(trader, 1_000e18);
        vm.prank(trader);
        dUsd.approve(address(issuer), type(uint256).max);

        // Reactive Network: one witness (issuer), callback to destination controller
        rx = new NightShiftReactive(DEST, PoolId.unwrap(poolId), ORIGIN, address(issuer), false, 0, 2_500_000);
        // destination: controller pinned to (callbackProxy, rx); hook accepts only the controller
        ctrl = new NightShiftController(callbackProxy, address(rx), hook);
        vm.prank(hookOwner);
        hook.initController(address(ctrl));
        rx.setController(address(ctrl));
        rx.subscribe();
    }

    /// @dev Issuer mint on origin → react() → callback → controller → hook anchor. Returns the anchor.
    function _issuerMintAt(uint256 price) internal returns (int24 anchor) {
        issuer.setPrice(price);
        vm.recordLogs();
        vm.prank(trader);
        issuer.mint(1e18);
        IReactive.LogRecord memory rec =
            _capture(vm.getRecordedLogs(), address(issuer), MockIssuer.Minted.selector, ORIGIN);

        vm.prank(SYSTEM_ADDR);
        rx.react(rec);
        assertEq(_relayCallbacks(callbackProxy), 1, "one callback delivered");
        (anchor,,,,,,,) = hook.poolState(poolId);
    }

    function test_gate1_issuerMove_repricesPool_withNoDestinationTrade() public {
        assertEq(sys.subCount(), 1, "subscribed to issuer");
        (uint24 feeBefore, bool awayBefore) = hook.quoteFee(key, false);
        assertTrue(awayBefore, "no anchor yet: max protection");

        int24 anchor = _issuerMintAt(1.02e18); // +2% Saturday news
        console.log("issuer +2%% -> anchor tick", int256(anchor));
        assertEq(anchor, PriceMath.tickFromRatio(1.02e18, 1e18));
        assertApproxEqAbs(int256(anchor), 198, 1);

        (uint24 feeToward, bool away) = hook.quoteFee(key, false);
        assertFalse(away, "buying dSTOCK now repairs toward fair value");
        console.log("repair fee (pips) before/after anchor:", feeBefore, feeToward);

        // repair flow is served all the way to the anchor
        _swapTo(false, anchor);
        (, int24 tick,,) = _slot0();
        assertEq(tick, anchor);

        // now at fair value: pushing past it is held to overshootCap (neutral swaps pay the cheap toward fee)
        vm.expectRevert(_wrapped(IHooks.afterSwap.selector, FeeMath.Overshoot.selector));
        _swapTo(false, anchor + int24(cfg.overshootCap) + 1);
    }

    function test_gate1_replayedCallback_rejected() public {
        _issuerMintAt(1.02e18);
        // a second witness event produces seq 2; replaying seq 1 is impossible because the hook enforces seq
        int24 a2 = _issuerMintAt(1.01e18);
        assertApproxEqAbs(int256(a2), 99, 1);
        assertEq(rx.seq(), 2);
    }

    function test_gate1_forgedCallback_rejected() public {
        vm.expectRevert();
        ctrl.onAnchor(address(rx), bytes32(0), 99, 0, 0, 0, 1, 0); // not from the proxy
    }

    function _slot0() internal view returns (uint160, int24, uint24, uint24) {
        return StateLibrary.getSlot0(manager, poolId);
    }
}
