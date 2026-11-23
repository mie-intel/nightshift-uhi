// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";

import {HookFixture} from "../utils/HookFixture.sol";
import {ControlClosedSurchargeHook} from "../../src/mocks/ControlClosedSurchargeHook.sol";
import {ControlFeeParams} from "../../src/libraries/Types.sol";
import {NightShiftConfig} from "../../script/utils/NightShiftConfig.sol";

contract ControlClosedSurchargeHookTest is HookFixture {
    ControlClosedSurchargeHook control;
    PoolKey controlKey;
    ControlFeeParams p;

    function setUp() public {
        _deployHookAndPool(_satNoon());
        p = NightShiftConfig.controlParams(NightShiftConfig.load("testnet"));
        address at = address(
            uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG)
                | (uint160(0x5555) << 144)
        );
        deployCodeTo("ControlClosedSurchargeHook.sol:ControlClosedSurchargeHook", abi.encode(manager, p), at);
        control = ControlClosedSurchargeHook(at);
        (controlKey,) = initPool(currency0, currency1, IHooks(at), LPFeeLibrary.DYNAMIC_FEE_FLAG, 60, SQRT_PRICE_1_1);
        modifyLiquidityRouter.modifyLiquidity(controlKey, ModifyLiquidityParams(-12_000, 12_000, 1e22, 0), ZERO_BYTES);
    }

    function _swap(bool zeroForOne, int24 target) internal {
        swapRouter.swap(
            controlKey,
            SwapParams(zeroForOne, -1e30, TickMath.getSqrtPriceAtTick(target)),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
    }

    function test_closed_atAnchor_bothDirectionsPayMidpointDrift() public view {
        uint256 expected =
            uint256(p.baseFee) + p.closedSurcharge + uint256(p.maxClosedMoveTicks / 2) * p.driftCoefficient;
        assertEq(control.quoteFee(controlKey, true), expected);
        assertEq(control.quoteFee(controlKey, false), expected);
    }

    function test_closed_towardPaysNoDrift_awayPaysDrift() public {
        _swap(false, 100);
        assertEq(control.quoteFee(controlKey, true), uint256(p.baseFee) + p.closedSurcharge, "toward");
        assertEq(
            control.quoteFee(controlKey, false),
            uint256(p.baseFee) + p.closedSurcharge + (100 + uint256(p.maxClosedMoveTicks / 2)) * p.driftCoefficient,
            "away"
        );
    }

    function test_closed_anchorStaysAtLastClose() public {
        _swap(false, 100);
        assertEq(control.anchorOf(controlKey.toId()), 0);
    }

    function test_closed_singleSwapMoveCapped() public {
        vm.expectRevert();
        _swap(false, int24(p.maxClosedMoveTicks) + 1);
        _swap(false, int24(p.maxClosedMoveTicks));
    }

    function test_open_baseFee_noMoveCap() public {
        vm.warp(_monOpen());
        assertEq(control.quoteFee(controlKey, true), p.baseFee);
        _swap(false, 1000);
    }
}
