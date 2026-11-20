// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AbstractCallback} from "@reactive/base/AbstractCallback.sol";
import {IPayable} from "@reactive/interfaces/IPayable.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {INightShiftController} from "../interfaces/INightShiftController.sol";
import {INightShiftHook} from "../interfaces/INightShiftHook.sol";
import {NyseCalendar} from "../libraries/NyseCalendar.sol";
import {Regime} from "../libraries/Types.sol";

/// @title NightShiftController
/// @notice Destination-chain receiver of Reactive callbacks (README §13.1). Authenticates every callback with BOTH
///         `onlyServiceProvider` (msg.sender == callback proxy) and `onlyCallbackSender` (injected first arg ==
///         our reactive contract) — ADR-008 — then fans out to the hook. Also holds the permissionless safety
///         fallbacks `syncRegime` (calendar) and `forceReconcile` (Reactive outage at the open).
/// @dev pragma ^0.8.29 because reactive-lib-omni's AbstractCallback requires it.
contract NightShiftController is AbstractCallback, INightShiftController {
    /// @notice Hook whose pool state this controller drives.
    INightShiftHook public immutable hook;
    /// @notice Seconds after entering REOPEN_PENDING before anyone may force the pool OPEN.
    uint256 public immutable reconcileTimeout;
    /// @notice When each pool entered REOPEN_PENDING (0 = not pending).
    mapping(bytes32 => uint256) public reopenPendingAt;

    /// @notice Calendar and pool regime already agree.
    error NothingToSync();
    /// @notice Pool is not waiting for reconciliation, or the timeout has not passed.
    error ReconcileNotDue();

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
    /// @notice A regime callback was applied.
    event RegimeRelayed(bytes32 indexed poolId, uint64 seq, uint8 regime, uint40 effectiveAt);
    /// @notice Reopen reconciliation applied (vault scoring lands with the vaults, Phase 8).
    event Reconciled(bytes32 indexed poolId, uint64 epochId, int24 openTick, uint40 openAt, bool degraded);
    /// @notice Permissionless calendar fallback changed the regime.
    event RegimeSynced(bytes32 indexed poolId, uint8 regime, address caller);
    /// @notice Permissionless reconcile-timeout fallback reopened the pool.
    event ForcedReconcile(bytes32 indexed poolId, address caller);

    /// @param callbackProxy_ Reactive callback proxy on this chain (README §18.2)
    /// @param reactive_ NightShiftReactive address on Reactive Network (callback sender identity)
    /// @param hook_ NightShiftHook
    /// @param reconcileTimeout_ seconds (config `quorum.reconcileTimeoutSeconds`)
    constructor(address callbackProxy_, address reactive_, INightShiftHook hook_, uint256 reconcileTimeout_)
        payable
        AbstractCallback(IPayable(payable(callbackProxy_)), reactive_)
    {
        hook = hook_;
        reconcileTimeout = reconcileTimeout_;
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

    /// @inheritdoc INightShiftController
    function onRegime(address reactive, bytes32 poolId, uint64 seq, uint8 regime, uint40 effectiveAt)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive)
    {
        hook.setRegime(PoolId.wrap(poolId), Regime(regime), seq);
        _trackReopen(poolId, Regime(regime));
        emit RegimeRelayed(poolId, seq, regime, effectiveAt);
    }

    /// @inheritdoc INightShiftController
    function onReconcile(
        address reactive,
        bytes32 poolId,
        uint64 seq,
        uint64 epochId,
        int24 openTick,
        uint40 openAt,
        bool degraded
    ) external onlyServiceProvider onlyCallbackSender(reactive) {
        hook.setRegime(PoolId.wrap(poolId), Regime.OPEN, seq);
        delete reopenPendingAt[poolId];
        emit Reconciled(poolId, epochId, openTick, openAt, degraded);
    }

    /// @notice Permissionless: align the pool regime with the NYSE calendar on this chain if Reactive is late
    ///         (README §6.3). OPEN→CLOSED when the market has closed; CLOSED→REOPEN_PENDING when it has opened.
    function syncRegime(bytes32 poolId) external {
        PoolId id = PoolId.wrap(poolId);
        bool open = NyseCalendar.isOpen(block.timestamp);
        Regime r = hook.regimeOf(id);
        Regime next;
        if (r == Regime.OPEN && !open) next = Regime.CLOSED;
        else if (r == Regime.CLOSED && open) next = Regime.REOPEN_PENDING;
        else revert NothingToSync();
        hook.forceRegime(id, next);
        _trackReopen(poolId, next);
        emit RegimeSynced(poolId, uint8(next), msg.sender);
    }

    /// @notice Permissionless: reopen the pool if reconciliation hasn't arrived within `reconcileTimeout`.
    function forceReconcile(bytes32 poolId) external {
        uint256 pendingSince = reopenPendingAt[poolId];
        if (pendingSince == 0 || block.timestamp < pendingSince + reconcileTimeout) revert ReconcileNotDue();
        if (hook.regimeOf(PoolId.wrap(poolId)) != Regime.REOPEN_PENDING) revert ReconcileNotDue();
        delete reopenPendingAt[poolId];
        hook.forceRegime(PoolId.wrap(poolId), Regime.OPEN);
        emit ForcedReconcile(poolId, msg.sender);
    }

    /// @notice Repay any outstanding callback debt to the proxy from this contract's balance (debt blocks callbacks).
    function coverDebt() external {
        _coverDebt();
    }

    function _trackReopen(bytes32 poolId, Regime r) internal {
        if (r == Regime.REOPEN_PENDING) reopenPendingAt[poolId] = block.timestamp;
        else if (r != Regime.HALTED) delete reopenPendingAt[poolId];
    }
}
