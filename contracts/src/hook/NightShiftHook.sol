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
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {INightShiftHook} from "../interfaces/INightShiftHook.sol";
import {FeeMath} from "../libraries/FeeMath.sol";
import {NyseCalendar} from "../libraries/NyseCalendar.sol";
import {RiskMath} from "../libraries/RiskMath.sol";
import {PoolConfig, Regime, RiskParams} from "../libraries/Types.sol";

/// @title NightShiftHook
/// @notice Dynamic-fee hook for tokenized-stock pools while Wall Street sleeps (SPEC §9, §13.1).
///         Toward-anchor (repair) swaps are served; away swaps pay risk-scaled fees and are size-capped.
///         Anchor/risk/regime are pushed by the Controller from Reactive callbacks, between trades.
/// @dev Closed-market fee ideas adapted from Gapguard (Bytethebuilder, MIT) — see FeeMath.
contract NightShiftHook is BaseOverrideFee, INightShiftHook {
    using StateLibrary for IPoolManager;

    /// @notice Per-pool state (SPEC §13.1, + `initialized`, + separate regime seq channel — ADR-017).
    struct PoolState {
        int24 anchorTick;
        uint40 anchorUpdatedAt;
        uint16 riskBps;
        uint16 dispersionTicks;
        Regime regime;
        uint64 lastSeq; // anchor channel
        bool curatedOnly;
        bool initialized;
        uint64 lastRegimeSeq; // regime channel
    }

    /// @dev Tick at the first capped-regime swap of a block (per-block away cap).
    struct MoveWindow {
        uint40 blockNumber;
        int24 startTick;
    }

    uint16 private constant MAX_RISK = 10_000;
    // transient slots: per-swap stash between beforeSwap and afterSwap = keccak256("nightshift.hook.<name>") - 1
    uint256 private constant T_TICK_BEFORE = 0x52712faf1c2a84b227ee359245ca57a8a04424e42578131f9e9cb1d8407200d2;
    uint256 private constant T_AWAY = 0x8f1438cec211b695a84b7c26c158b0c1acdfc7f3d330759fca85750be070c093;
    uint256 private constant T_RISK = 0xae686ccf4ba1908ba8f2ad1154fdf57092c54365b4a9bab1830c20bf799e76c4;
    uint256 private constant T_FEE = 0x54a5e3b24752a83274eea4d25dae12a367ba4e2d62c62e16f820f96081d31072;

    /// @notice May set the Controller once.
    address public immutable owner;
    /// @notice Only address allowed to mutate pool state.
    address public controller;
    /// @notice Local divergence full-scale (ticks) for `riskUsed = max(stored, local)` (SPEC §8.3).
    uint24 public immutable divergenceFullTicks;
    /// @notice Local divergence weight (bps of risk) — same weight the Reactive risk score uses.
    uint16 public immutable divergenceWeight;
    /// @notice Fee policy applied to every pool of this hook (v0: one config; registry-driven per-pool in Phase 7).
    PoolConfig internal _config;
    /// @notice State per pool.
    mapping(PoolId => PoolState) public poolState;
    /// @dev AnchorStale already emitted for the current stale period.
    mapping(PoolId => bool) internal _staleFlagged;
    /// @dev Per-pool reference for the per-block away cap.
    mapping(PoolId => MoveWindow) internal _moveWindow;

    /// @notice Caller is not the Controller.
    error NotController();
    /// @notice Caller is not the owner.
    error NotOwner();
    /// @notice Controller already set.
    error ControllerAlreadySet();
    /// @notice `seq` not greater than the pool's last seq (replay/reorder).
    error StaleSeq();
    /// @notice Pool was not initialized with this hook.
    error UnknownPool();

    /// @notice Controller set (once).
    event ControllerSet(address controller);
    /// @notice Pool initialized with its calendar regime.
    event PoolRegistered(PoolId indexed id, Regime regime);
    /// @notice Anchor/risk updated from a Reactive callback.
    event AnchorUpdated(PoolId indexed id, int24 anchorTick, uint16 riskBps, uint16 dispersionTicks, uint64 seq);
    /// @notice Regime changed by a Reactive callback.
    event RegimeSet(PoolId indexed id, Regime regime, uint64 seq);
    /// @notice Regime changed by a permissionless Controller fallback (calendar / reconcile timeout).
    event RegimeForced(PoolId indexed id, Regime regime);
    /// @notice Anchor is stale: max protection applies (emitted once per stale period).
    event AnchorStale(PoolId indexed id);
    /// @notice A swap passed fee + caps.
    event SwapObserved(PoolId indexed id, int24 tickBefore, int24 tickAfter, uint24 fee, bool away);

    /// @param poolManager_ v4 PoolManager
    /// @param config_ fee policy (from contracts/config/*.json), validated against hard caps
    /// @param risk_ risk params (from config `risk`); only the divergence pair is used on-chain here
    /// @param owner_ account allowed to set the Controller once (CREATE2 deploys make msg.sender the factory)
    constructor(IPoolManager poolManager_, PoolConfig memory config_, RiskParams memory risk_, address owner_)
        BaseHook(poolManager_)
    {
        FeeMath.validate(config_);
        RiskMath.validate(risk_);
        _config = config_;
        divergenceFullTicks = risk_.divergenceFullTicks;
        divergenceWeight = risk_.weightDivergence;
        owner = owner_;
    }

    modifier onlyController() {
        if (msg.sender != controller) revert NotController();
        _;
    }

    /// @notice Set the Controller (once). Hook state can only change through it afterwards (invariant 1).
    function initController(address controller_) external {
        if (msg.sender != owner) revert NotOwner();
        if (controller != address(0)) revert ControllerAlreadySet();
        controller = controller_;
        emit ControllerSet(controller_);
    }

    /// @notice Fee policy in force.
    function config() external view returns (PoolConfig memory) {
        return _config;
    }

    /// @inheritdoc INightShiftHook
    function setState(PoolId id, int24 anchorTick, uint16 riskBps, uint16 dispersionTicks, uint64 seq)
        external
        onlyController
    {
        PoolState storage s = _checkedSeq(id, seq);
        s.anchorTick = anchorTick;
        s.anchorUpdatedAt = uint40(block.timestamp);
        s.riskBps = riskBps > MAX_RISK ? MAX_RISK : riskBps;
        s.dispersionTicks = dispersionTicks;
        _staleFlagged[id] = false;
        emit AnchorUpdated(id, anchorTick, s.riskBps, dispersionTicks, seq);
    }

    /// @inheritdoc INightShiftHook
    function setRegime(PoolId id, Regime regime, uint64 seq) external onlyController {
        PoolState storage s = poolState[id];
        if (!s.initialized) revert UnknownPool();
        if (seq <= s.lastRegimeSeq) revert StaleSeq();
        s.lastRegimeSeq = seq;
        s.regime = regime;
        emit RegimeSet(id, regime, seq);
    }

    /// @inheritdoc INightShiftHook
    function forceRegime(PoolId id, Regime regime) external onlyController {
        PoolState storage s = poolState[id];
        if (!s.initialized) revert UnknownPool();
        s.regime = regime;
        emit RegimeForced(id, regime);
    }

    /// @inheritdoc INightShiftHook
    function anchorOf(PoolId id) external view returns (int24) {
        return poolState[id].anchorTick;
    }

    /// @inheritdoc INightShiftHook
    function regimeOf(PoolId id) external view returns (Regime) {
        return poolState[id].regime;
    }

    /// @inheritdoc INightShiftHook
    function quoteFee(PoolKey calldata key, bool zeroForOne) external view returns (uint24 fee, bool away) {
        (fee, away,,,) = _quote(key.toId(), zeroForOne);
    }

    /// @notice afterInitialize + beforeAddLiquidity + beforeSwap + afterSwap; no return-delta flags.
    function getHookPermissions() public pure override returns (Hooks.Permissions memory p) {
        p.afterInitialize = true;
        p.beforeAddLiquidity = true;
        p.beforeSwap = true;
        p.afterSwap = true;
    }

    // ---------------------------------------------------------------- hooks

    function _afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick)
        internal
        override
        returns (bytes4)
    {
        super._afterInitialize(sender, key, sqrtPriceX96, tick); // reverts NotDynamicFee
        PoolId id = key.toId();
        Regime r = NyseCalendar.regimeAt(block.timestamp);
        PoolState storage s = poolState[id];
        s.initialized = true;
        s.regime = r;
        emit PoolRegistered(id, r);
        return this.afterInitialize.selector;
    }

    /// @dev `curatedOnly` gate lands with the registry (Phase 7); open to all LPs in v0.
    function _beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        pure
        override
        returns (bytes4)
    {
        return this.beforeAddLiquidity.selector;
    }

    function _getFee(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (uint24 fee)
    {
        PoolId id = key.toId();
        bool away;
        uint16 riskUsed;
        int24 tick;
        bool stale;
        (fee, away, riskUsed, tick, stale) = _quote(id, params.zeroForOne);
        if (stale && !_staleFlagged[id]) {
            _staleFlagged[id] = true;
            emit AnchorStale(id);
        }
        assembly ("memory-safe") {
            tstore(T_TICK_BEFORE, tick)
            tstore(T_AWAY, away)
            tstore(T_RISK, riskUsed)
            tstore(T_FEE, fee)
        }
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata params, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        PoolId id = key.toId();
        (, int24 tickAfter,,) = poolManager.getSlot0(id);
        (int24 tickBefore, bool away) = _enforceMoveCaps(id, params.zeroForOne, tickAfter);
        uint24 fee;
        assembly ("memory-safe") {
            fee := tload(T_FEE)
        }
        emit SwapObserved(id, tickBefore, tickAfter, fee, away);
        return (this.afterSwap.selector, 0);
    }

    // ---------------------------------------------------------------- internal

    /// @dev Fee for a swap now. Stale or never-set anchor → treat as away at max risk (SPEC §9.4).
    function _quote(PoolId id, bool zeroForOne)
        internal
        view
        returns (uint24 fee, bool away, uint16 riskUsed, int24 tick, bool stale)
    {
        PoolState storage s = poolState[id];
        (, tick,,) = poolManager.getSlot0(id);
        uint256 maxAge = s.regime == Regime.OPEN ? _config.anchorMaxAgeOpen : _config.anchorMaxAgeClosed;
        stale = s.anchorUpdatedAt == 0 || block.timestamp - s.anchorUpdatedAt > maxAge;
        uint256 absD;
        if (stale) {
            away = true;
            riskUsed = MAX_RISK;
        } else {
            (away, absD) = FeeMath.direction(tick, s.anchorTick, zeroForOne, _config.deadbandTicks);
            // a late callback can't make fees too cheap: local divergence is a floor (SPEC §8.3)
            uint256 local = uint256(divergenceWeight) * RiskMath.component(absD, divergenceFullTicks) / 10_000;
            riskUsed = local > s.riskBps ? uint16(local) : s.riskBps;
        }
        fee = FeeMath.fee(_config, s.regime, away, absD, riskUsed);
    }

    /// @dev Move caps (SPEC §9.3) using the per-swap stash written in beforeSwap.
    function _enforceMoveCaps(PoolId id, bool zeroForOne, int24 tickAfter)
        internal
        returns (int24 tickBefore, bool away)
    {
        uint16 riskUsed;
        assembly ("memory-safe") {
            tickBefore := tload(T_TICK_BEFORE)
            away := tload(T_AWAY)
            riskUsed := tload(T_RISK)
        }
        PoolState storage s = poolState[id];
        FeeMath.checkMove(_config, s.regime, away, riskUsed, s.anchorTick, zeroForOne, tickBefore, tickAfter);
        if (s.regime == Regime.OPEN) return (tickBefore, away);
        MoveWindow storage w = _moveWindow[id];
        if (w.blockNumber != block.number) {
            w.blockNumber = uint40(block.number);
            w.startTick = tickBefore;
        }
        if (away) FeeMath.checkBlockMove(_config, riskUsed, zeroForOne, w.startTick, tickAfter);
    }

    function _checkedSeq(PoolId id, uint64 seq) internal returns (PoolState storage s) {
        s = poolState[id];
        if (!s.initialized) revert UnknownPool();
        if (seq <= s.lastSeq) revert StaleSeq();
        s.lastSeq = seq;
    }
}
