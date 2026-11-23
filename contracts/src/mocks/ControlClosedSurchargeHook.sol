// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseOverrideFee} from "@openzeppelin/uniswap-hooks/src/fee/BaseOverrideFee.sol";
import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {NyseCalendar} from "../libraries/NyseCalendar.sol";
import {ControlFeeParams} from "../libraries/Types.sol";

/// @title ControlClosedSurchargeHook
/// @notice Scenario baseline modeled on Gapguard (Bytethebuilder, MIT): closed-market surcharge, drift fee for swaps
///         moving away from the last-close anchor, and a per-swap move cap. Testnet/test use only.
/// @dev Simplifications: the anchor stays at the pool's initial tick (scenarios run inside one closed period), and
///      Gapguard's hook skim is not modeled, so LPs keep the whole surcharge.
contract ControlClosedSurchargeHook is BaseOverrideFee {
    using StateLibrary for IPoolManager;

    // keccak256("nightshift.control.tickBefore") - 1
    uint256 private constant T_TICK_BEFORE = 0x9013723f012131eb280115d4f07836777098804954268686269db5b3533ff8ea;

    /// @notice Fee parameters.
    ControlFeeParams public params;
    /// @notice Last-close anchor per pool.
    mapping(PoolId => int24) public anchorOf;

    /// @notice A closed-market swap moved the tick more than the cap.
    error ClosedMoveTooLarge();

    /// @param poolManager_ v4 PoolManager
    /// @param params_ fee parameters (config `gapguardControl`)
    constructor(IPoolManager poolManager_, ControlFeeParams memory params_) BaseHook(poolManager_) {
        params = params_;
    }

    /// @notice afterInitialize + beforeSwap + afterSwap.
    function getHookPermissions() public pure override returns (Hooks.Permissions memory p) {
        p.afterInitialize = true;
        p.beforeSwap = true;
        p.afterSwap = true;
    }

    /// @notice LP fee a swap in this direction pays now, in pips.
    function quoteFee(PoolKey calldata key, bool zeroForOne) external view returns (uint24) {
        PoolId id = key.toId();
        (, int24 tick,,) = poolManager.getSlot0(id);
        return _fee(tick, anchorOf[id], zeroForOne);
    }

    function _afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick)
        internal
        override
        returns (bytes4)
    {
        super._afterInitialize(sender, key, sqrtPriceX96, tick); // reverts NotDynamicFee
        anchorOf[key.toId()] = tick;
        return this.afterInitialize.selector;
    }

    function _getFee(address, PoolKey calldata key, SwapParams calldata swap, bytes calldata)
        internal
        override
        returns (uint24)
    {
        PoolId id = key.toId();
        (, int24 tick,,) = poolManager.getSlot0(id);
        assembly ("memory-safe") {
            tstore(T_TICK_BEFORE, tick)
        }
        return _fee(tick, anchorOf[id], swap.zeroForOne);
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        if (!NyseCalendar.isOpen(block.timestamp)) {
            int24 tickBefore;
            assembly ("memory-safe") {
                tickBefore := tload(T_TICK_BEFORE)
            }
            (, int24 tickAfter,,) = poolManager.getSlot0(key.toId());
            if (_abs(int256(tickAfter) - tickBefore) > params.maxClosedMoveTicks) revert ClosedMoveTooLarge();
        }
        return (this.afterSwap.selector, 0);
    }

    function _fee(int24 tick, int24 anchor, bool zeroForOne) internal view returns (uint24) {
        ControlFeeParams memory p = params;
        if (NyseCalendar.isOpen(block.timestamp)) return p.baseFee;
        int256 drift = int256(tick) - anchor;
        uint256 f = uint256(p.baseFee) + p.closedSurcharge;
        if ((drift > 0 && zeroForOne) || (drift < 0 && !zeroForOne)) return uint24(f);
        uint256 surcharge = (_abs(drift) + p.maxClosedMoveTicks / 2) * p.driftCoefficient;
        return uint24(f + (surcharge > p.maxDriftSurcharge ? p.maxDriftSurcharge : surcharge));
    }

    function _abs(int256 x) internal pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }
}
