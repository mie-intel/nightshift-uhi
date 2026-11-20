// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AbstractCallback} from "@reactive/base/AbstractCallback.sol";
import {IPayable} from "@reactive/interfaces/IPayable.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {INightShiftController} from "../interfaces/INightShiftController.sol";
import {INightShiftHook} from "../interfaces/INightShiftHook.sol";

/// @title NightShiftController
/// @notice Destination-chain receiver of Reactive callbacks (README §13.1). Authenticates every callback with BOTH
///         `onlyServiceProvider` (msg.sender == callback proxy) and `onlyCallbackSender` (injected first arg ==
///         our reactive contract) — ADR-008 — then fans out to the hook.
/// @dev pragma ^0.8.29 because reactive-lib-omni's AbstractCallback requires it.
contract NightShiftController is AbstractCallback, INightShiftController {
    /// @notice Hook whose pool state this controller drives.
    INightShiftHook public immutable hook;

    /// @notice An anchor callback was applied to the hook.
    event AnchorRelayed(
        bytes32 indexed poolId,
        uint64 seq,
        int24 anchorTick,
        uint16 riskBps,
        uint16 dispersionTicks,
        uint8 sources,
        uint40 observedAt
    );

    /// @param callbackProxy_ Reactive callback proxy on this chain (README §18.2)
    /// @param reactive_ NightShiftReactive address on Reactive Network (callback sender identity)
    /// @param hook_ NightShiftHook
    constructor(address callbackProxy_, address reactive_, INightShiftHook hook_)
        payable
        AbstractCallback(IPayable(payable(callbackProxy_)), reactive_)
    {
        hook = hook_;
    }

    /// @inheritdoc INightShiftController
    function onAnchor(
        address reactive,
        bytes32 poolId,
        uint64 seq,
        int24 anchorTick,
        uint16 riskBps,
        uint16 dispersionTicks,
        uint8 sources,
        uint40 observedAt
    ) external onlyServiceProvider onlyCallbackSender(reactive) {
        hook.setState(PoolId.wrap(poolId), anchorTick, riskBps, dispersionTicks, seq);
        emit AnchorRelayed(poolId, seq, anchorTick, riskBps, dispersionTicks, sources, observedAt);
    }

    /// @notice Repay any outstanding callback debt to the proxy from this contract's balance (debt blocks callbacks).
    function coverDebt() external {
        _coverDebt();
    }
}
