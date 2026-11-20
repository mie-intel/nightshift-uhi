// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title INightShiftController
/// @notice Reactive callback entry points (SPEC §13.1). The first argument is always the reactive identity,
///         sent as address(0) by the reactive contract and overwritten by the callback proxy.
interface INightShiftController {
    /// @notice New anchor/risk for a pool (anchor seq channel).
    function onAnchor(
        address reactive,
        bytes32 poolId,
        uint64 seq,
        int24 anchorTick,
        uint16 riskBps,
        uint16 dispersionTicks,
        uint8 sources,
        uint40 observedAt
    ) external;

    /// @notice Market regime transition (regime seq channel).
    function onRegime(address reactive, bytes32 poolId, uint64 seq, uint8 regime, uint40 effectiveAt) external;

    /// @notice Reopen reconciliation: open tick witnessed during the open window (regime seq channel).
    function onReconcile(
        address reactive,
        bytes32 poolId,
        uint64 seq,
        uint64 epochId,
        int24 openTick,
        uint40 openAt,
        bool degraded
    ) external;
}
