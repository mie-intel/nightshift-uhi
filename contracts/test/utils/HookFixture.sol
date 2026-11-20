// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {CustomRevert} from "@uniswap/v4-core/src/libraries/CustomRevert.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {NightShiftHook} from "../../src/hook/NightShiftHook.sol";
import {DemoToken} from "../../src/mocks/DemoToken.sol";
import {NyseCalendar} from "../../src/libraries/NyseCalendar.sol";
import {PoolConfig} from "../../src/libraries/Types.sol";
import {NightShiftConfig} from "../../script/utils/NightShiftConfig.sol";

/// @notice Local v4 PoolManager + test routers + NightShiftHook + one dynamic-fee pool with deep liquidity at tick 0.
/// @dev Compiles under both 0.8.26 and 0.8.29: PoolManager comes from its artifact (see V4Artifacts.sol).
abstract contract HookFixture is Test {
    uint160 internal constant HOOK_FLAGS =
        Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG;
    uint160 internal constant SQRT_PRICE_1_1 = 79_228_162_514_264_337_593_543_950_336;
    bytes internal constant ZERO_BYTES = "";

    IPoolManager internal manager;
    PoolSwapTest internal swapRouter;
    PoolModifyLiquidityTest internal modifyLiquidityRouter;
    Currency internal currency0;
    Currency internal currency1;
    PoolKey internal key;

    NightShiftHook internal hook;
    PoolConfig internal cfg;
    PoolId internal poolId;
    address internal hookOwner = makeAddr("hookOwner");

    /// @dev Sat 21 Nov 2026 12:00 UTC — market CLOSED.
    function _satNoon() internal pure returns (uint256) {
        return NyseCalendar.daysFromCivil(2026, 11, 21) * 1 days + 12 hours;
    }

    /// @dev Mon 23 Nov 2026 15:00 UTC — market OPEN.
    function _monOpen() internal pure returns (uint256) {
        return NyseCalendar.daysFromCivil(2026, 11, 23) * 1 days + 15 hours;
    }

    function _deployHookAndPool(uint256 initTime) internal {
        vm.warp(initTime);
        string memory json = NightShiftConfig.load("testnet");
        cfg = NightShiftConfig.poolConfig(json);

        manager = IPoolManager(deployCode("PoolManager.sol:PoolManager", abi.encode(address(this))));
        swapRouter = new PoolSwapTest(manager);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        (currency0, currency1) = _deployCurrencies();

        address hookAddr = address(HOOK_FLAGS | (uint160(0x4444) << 144));
        deployCodeTo("NightShiftHook.sol:NightShiftHook", abi.encode(manager, cfg, hookOwner), hookAddr);
        hook = NightShiftHook(hookAddr);

        (key, poolId) = initPool(
            currency0,
            currency1,
            IHooks(hookAddr),
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            NightShiftConfig.tickSpacing(json),
            SQRT_PRICE_1_1
        );
        modifyLiquidityRouter.modifyLiquidity(key, ModifyLiquidityParams(-12_000, 12_000, 1e22, 0), ZERO_BYTES);
    }

    function _deployCurrencies() internal returns (Currency c0, Currency c1) {
        DemoToken a = new DemoToken("Pool Stock", "pSTOCK", 18);
        DemoToken b = new DemoToken("Pool USD", "pUSD", 18);
        DemoToken[2] memory ts = [a, b];
        for (uint256 i; i < 2; i++) {
            ts[i].mint(address(this), 2 ** 200);
            ts[i].approve(address(swapRouter), type(uint256).max);
            ts[i].approve(address(modifyLiquidityRouter), type(uint256).max);
        }
        (c0, c1) = address(a) < address(b)
            ? (Currency.wrap(address(a)), Currency.wrap(address(b)))
            : (Currency.wrap(address(b)), Currency.wrap(address(a)));
    }

    function initPool(Currency c0, Currency c1, IHooks hooks, uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96)
        internal
        returns (PoolKey memory k, PoolId id)
    {
        k = PoolKey(c0, c1, fee, tickSpacing, hooks);
        id = k.toId();
        manager.initialize(k, sqrtPriceX96);
    }

    /// @dev Exact-input swap that stops at `targetTick` (price limit).
    function _swapTo(bool zeroForOne, int24 targetTick) internal returns (BalanceDelta) {
        return swapRouter.swap(
            key,
            SwapParams(zeroForOne, -1e30, TickMath.getSqrtPriceAtTick(targetTick)),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
    }

    /// @dev Revert data PoolManager produces when a hook call reverts with `inner`.
    function _wrapped(bytes4 hookSelector, bytes4 inner) internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            CustomRevert.WrappedError.selector,
            address(hook),
            hookSelector,
            abi.encodeWithSelector(inner),
            abi.encodeWithSelector(Hooks.HookCallFailed.selector)
        );
    }
}
