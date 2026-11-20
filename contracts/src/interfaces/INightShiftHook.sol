// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Regime} from "../libraries/Types.sol";

/// @title INightShiftHook
/// @notice Controller-facing surface of the NightShift hook (SPEC §13.1).
interface INightShiftHook {
    /// @notice Push a new anchor/risk snapshot. Only Controller; `seq` must exceed the pool's last seq.
    function setState(PoolId id, int24 anchorTick, uint16 riskBps, uint16 dispersionTicks, uint64 seq) external;

    /// @notice Set the pool regime. Only Controller; `seq` must exceed the pool's last seq.
    function setRegime(PoolId id, Regime regime, uint64 seq) external;

    /// @notice Set the regime without a seq (Controller fallbacks only: calendar sync, reconcile timeout).
    function forceRegime(PoolId id, Regime regime) external;

    /// @notice Last anchor tick pushed for a pool.
    function anchorOf(PoolId id) external view returns (int24);

    /// @notice Current regime of a pool.
    function regimeOf(PoolId id) external view returns (Regime);

    /// @notice Fee a swap in direction `zeroForOne` would pay right now.
    function quoteFee(PoolKey calldata key, bool zeroForOne) external view returns (uint24 fee, bool away);
}
