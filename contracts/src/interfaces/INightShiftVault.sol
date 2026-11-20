// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Regime} from "../libraries/Types.sol";

/// @title INightShiftVault
/// @notice Controller-facing surface of a curator vault (SPEC §10.3, §11).
interface INightShiftVault {
    /// @notice Recenter liquidity on the witnessed fair price per the curator's mandate (onlyController).
    function rebalance(int24 anchorTick, uint16 riskBps, Regime regime) external;

    /// @notice Record per-share composition at market close (onlyController).
    function snapshotClose(uint64 epochId) external;

    /// @notice Score the epoch vs HODL at the witnessed open tick; perf fee above HWM (onlyController).
    function reconcile(uint64 epochId, int24 openTick, bool degraded) external;
}
