// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AbstractReactive} from "@reactive/base/AbstractReactive.sol";
import {ISystemContract} from "@reactive/interfaces/ISystemContract.sol";

import {INightShiftController} from "../interfaces/INightShiftController.sol";
import {NyseCalendar} from "../libraries/NyseCalendar.sol";
import {PriceMath} from "../libraries/PriceMath.sol";
import {RiskMath} from "../libraries/RiskMath.sol";
import {WitnessMath} from "../libraries/WitnessMath.sol";
import {GasLimits, QuorumParams, Regime, RiskParams, SourceKind, WitnessSource} from "../libraries/Types.sol";

/// @title NightShiftReactive
/// @notice Runs on Reactive Network. Subscribes to witness events on several chains (issuer mint/redeem, sibling
///         Uniswap v4 pools, the destination pool itself) plus Cron, and pushes state into the destination pool
///         between trades (SPEC §7, §8, §13.2):
///         - Witness Quorum: per-source influence cap + time-weighted EWMA; anchor = weighted median of fresh
///           sources; quorum needs `minQuorumWeight` AND `minDistinctChains`.
///         - Gap Risk Score: time/dispersion/divergence/staleness; ratchets up while closed.
///         - Regime from the NYSE calendar on every Cron tick (Cron1000 by default): OPEN → CLOSED → REOPEN_PENDING → (reconcile) → OPEN.
///         - Callbacks: `onAnchor` (debounced), `onRegime` and `onReconcile` (never debounced), monotonic `seq`.
/// @dev One pool per reactive contract. `react()` must stay < 900k gas: sources capped at MAX_SOURCES.
contract NightShiftReactive is AbstractReactive {
    /// @notice Max witness sources (bounded loops).
    uint256 public constant MAX_SOURCES = 16;
    /// @notice Legacy system contract that emits Cron events on Reactive Network.
    address public constant CRON_EMITTER = 0x0000000000000000000000000000000000fffFfF;
    /// @notice Cron topic subscribed to (config `cron.topic0`; Cron1000 ~17 min by default — ADR-017).
    uint256 public immutable cronTopic;
    /// @notice `MockIssuer.Minted(address,uint256,uint256)`.
    uint256 public constant MINTED_TOPIC0 = uint256(keccak256("Minted(address,uint256,uint256)"));
    /// @notice `MockIssuer.Redeemed(address,uint256,uint256)`.
    uint256 public constant REDEEMED_TOPIC0 = uint256(keccak256("Redeemed(address,uint256,uint256)"));
    /// @notice v4 `PoolManager.Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)`.
    uint256 public constant V4_SWAP_TOPIC0 =
        uint256(keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)"));

    /// @notice Callback kinds (event tag).
    uint8 public constant KIND_ANCHOR = 0;
    uint8 public constant KIND_REGIME = 1;
    uint8 public constant KIND_RECONCILE = 2;

    /// @notice Per-source rolling state.
    struct SourceState {
        int24 ewma;
        int24 lastRaw;
        uint40 lastSeen;
    }

    /// @notice Admin (sources, controller, pause).
    address public immutable owner;
    /// @notice Destination chain id.
    uint256 public immutable destChainId;
    /// @notice Destination pool id.
    bytes32 public immutable poolId;

    QuorumParams internal _q;
    RiskParams internal _r;
    GasLimits internal _g;
    WitnessSource[] internal _sources;
    SourceState[] internal _state;

    /// @notice Destination Controller.
    address public controller;
    /// @notice Stops processing (events are ignored) while true.
    bool public paused;

    /// @notice Current regime as tracked here.
    Regime public regime;
    /// @notice Monotonic callback sequence (shared counter; hook checks anchor/regime channels separately).
    uint64 public seq;
    /// @notice Closed-period counter, ++ on each OPEN→CLOSED.
    uint64 public epochId;
    /// @notice Whether an anchor has ever been computed with quorum.
    bool public hasAnchor;
    /// @notice Quorum state at the last refresh.
    bool public quorum;
    /// @notice Latest anchor (destination ticks).
    int24 public anchor;
    /// @notice Weighted MAD of fresh witnesses (ticks).
    uint16 public dispersion;
    /// @notice Gap Risk Score, bps.
    uint16 public riskBps;
    /// @notice Destination pool tick from its own swaps (divergence input).
    int24 public selfTick;
    /// @notice Whether `selfTick` has been observed.
    bool public hasSelf;
    /// @notice Debounce memory.
    int24 public lastSentAnchor;
    uint16 public lastSentRisk;
    uint40 public lastCallbackAt;
    bool public sentOnce;
    /// @notice Risk/regime clocks.
    uint40 public lastQuorumAt;
    uint40 public lastOpenAnchorAt;
    uint40 public reopenAt;

    /// @notice Caller is not the owner.
    error NotOwner();
    /// @notice Controller not configured yet.
    error ControllerNotSet();
    /// @notice react() received a log that matches no source.
    error UnexpectedLog();
    /// @notice Too many sources.
    error TooManySources();
    /// @notice Gas limit below Reactive's 100k minimum.
    error GasTooLow();

    /// @notice Controller configured.
    event ControllerSet(address controller);
    /// @notice Witness source added (and subscribed).
    event SourceAdded(uint256 indexed index, uint256 chainId, address emitter, SourceKind kind, uint16 weight);
    /// @notice Witness source disabled (and unsubscribed).
    event SourceDisabled(uint256 indexed index);
    /// @notice Subscribed to Cron.
    event CronSubscribed(uint256 topic0);
    /// @notice Funds withdrawn by the owner (recover lREACT before a redeploy).
    event Withdrawn(address to, uint256 amount);
    /// @notice Paused / unpaused.
    event PausedSet(bool paused);
    /// @notice A witness observation was processed (SPEC §14.4). `destTick` raw, `ewma` smoothed (clamped).
    event WitnessObserved(uint256 indexed source, uint256 chainId, int24 destTick, int24 ewma);
    /// @notice Quorum/anchor/risk recomputed (SPEC §14.4).
    event QuorumComputed(bool quorum, int24 anchor, uint16 dispersion, uint16 riskBps, uint8 sources, uint8 chains);
    /// @notice Regime transition detected on Cron.
    event RegimeChanged(Regime regime, uint64 epochId);
    /// @notice A callback was requested (SPEC §14.4).
    event CallbackRequested(uint8 indexed kind, uint64 seq, int24 anchorTick, uint16 riskBps, uint8 regime);

    constructor(
        uint256 destChainId_,
        bytes32 poolId_,
        QuorumParams memory q_,
        RiskParams memory r_,
        GasLimits memory g_,
        uint256 cronTopic_
    ) payable {
        RiskMath.validate(r_);
        if (g_.onAnchor < 100_000 || g_.onRegime < 100_000 || g_.onReconcile < 100_000) revert GasTooLow();
        owner = msg.sender;
        destChainId = destChainId_;
        poolId = poolId_;
        cronTopic = cronTopic_;
        _q = q_;
        _r = r_;
        _g = g_;
        regime = NyseCalendar.regimeAt(block.timestamp);
        lastQuorumAt = uint40(block.timestamp);
        lastOpenAnchorAt = uint40(block.timestamp);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ---------------------------------------------------------------- admin

    /// @notice Set the destination Controller (deployed after this contract, since it pins our address).
    function setController(address controller_) external onlyOwner {
        controller = controller_;
        emit ControllerSet(controller_);
    }

    /// @notice Add a witness source and subscribe to its event (one subscription per source; Omni has no OR).
    function addSource(WitnessSource calldata s) external onlyOwner returns (uint256 index) {
        if (_sources.length >= MAX_SOURCES) revert TooManySources();
        index = _sources.length;
        _sources.push(s);
        _state.push();
        if (s.enabled) SYSTEM.subscribe(s.chainId, s.emitter, s.topic0, s.topic1, REACTIVE_IGNORE, REACTIVE_IGNORE);
        emit SourceAdded(index, s.chainId, s.emitter, s.kind, s.weight);
    }

    /// @notice Disable a source and drop its subscription.
    function disableSource(uint256 index) external onlyOwner {
        WitnessSource storage s = _sources[index];
        if (!s.enabled) return;
        s.enabled = false;
        SYSTEM.unsubscribe(s.chainId, s.emitter, s.topic0, s.topic1, REACTIVE_IGNORE, REACTIVE_IGNORE);
        emit SourceDisabled(index);
    }

    /// @notice Subscribe to Cron (regime transitions, heartbeat, staleness). Bills every tick.
    function subscribeCron() external onlyOwner {
        SYSTEM.subscribe(block.chainid, CRON_EMITTER, cronTopic, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
        emit CronSubscribed(cronTopic);
    }

    /// @notice Owner recovers funds (e.g. before redeploying). Leaves debt handling to `coverDebt`.
    function withdraw(address payable to, uint256 amount) external onlyOwner {
        _pay(to, amount);
        emit Withdrawn(to, amount);
    }

    /// @notice Pause/unpause processing.
    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
        emit PausedSet(paused_);
    }

    /// @notice Repay any outstanding debt to SYSTEM from this contract's balance (debt blocks execution).
    function coverDebt() external {
        _coverDebt();
    }

    // ---------------------------------------------------------------- views

    /// @notice Number of sources.
    function sourceCount() external view returns (uint256) {
        return _sources.length;
    }

    /// @notice Source config + rolling state.
    function sourceAt(uint256 i) external view returns (WitnessSource memory, SourceState memory) {
        return (_sources[i], _state[i]);
    }

    /// @notice Quorum/risk params.
    function params() external view returns (QuorumParams memory, RiskParams memory, GasLimits memory) {
        return (_q, _r, _g);
    }

    // ---------------------------------------------------------------- react

    /// @notice Entry point for subscribed logs (Cron or witness events).
    function react(LogRecord calldata log_) external onlySystem {
        if (paused) return;
        if (controller == address(0)) revert ControllerNotSet();
        if (log_.contractAddress == CRON_EMITTER && log_.topic0 == cronTopic) {
            _onCron();
            return;
        }
        uint256 i = _findSource(log_);
        WitnessSource storage s = _sources[i];
        (bool ok, int24 srcTick, uint256 notional) = _decode(s.kind, log_.data);
        if (!ok || notional < s.minNotional) return;
        int24 x = PriceMath.normalize(srcTick, s.invert, s.offsetTicks);

        if (s.kind == SourceKind.SELF) {
            selfTick = x;
            hasSelf = true;
            emit WitnessObserved(i, log_.chainId, x, x);
        } else {
            SourceState storage st = _state[i];
            int24 capped = hasAnchor ? WitnessMath.clamp(x, anchor, _q.maxJumpTicks) : x;
            st.ewma = st.lastSeen == 0
                ? capped
                : WitnessMath.ewma(st.ewma, capped, block.timestamp - st.lastSeen, _q.halfLifeSeconds);
            st.lastRaw = x;
            st.lastSeen = uint40(block.timestamp);
            emit WitnessObserved(i, log_.chainId, x, st.ewma);
        }
        _refresh(false);
    }

    // ---------------------------------------------------------------- internals: regime

    function _onCron() internal {
        bool open = NyseCalendar.isOpen(block.timestamp);
        if (regime == Regime.OPEN && !open) {
            regime = Regime.CLOSED;
            ++epochId;
            emit RegimeChanged(Regime.CLOSED, epochId);
            _sendRegime(Regime.CLOSED);
        } else if (regime == Regime.CLOSED && open) {
            regime = Regime.REOPEN_PENDING;
            reopenAt = uint40(block.timestamp);
            emit RegimeChanged(Regime.REOPEN_PENDING, epochId);
            _sendRegime(Regime.REOPEN_PENDING);
        } else if (regime == Regime.REOPEN_PENDING) {
            _refresh(false); // issuer weight boosted during the open window
            uint256 since = block.timestamp - reopenAt;
            if (since >= _q.openWindowSeconds && (quorum || since >= _q.reconcileTimeoutSeconds)) {
                _sendReconcile(!quorum);
                regime = Regime.OPEN;
                riskBps = 0;
                lastOpenAnchorAt = uint40(block.timestamp);
                emit RegimeChanged(Regime.OPEN, epochId);
                _refresh(true); // push risk 0 + fresh anchor
            }
            return;
        }
        _refresh(false); // heartbeat + staleness
    }

    // ---------------------------------------------------------------- internals: quorum + risk

    function _refresh(bool force) internal {
        (bool q, int24 a, uint16 disp, uint8 n, uint8 chains) = _computeQuorum();
        quorum = q;
        if (q) {
            anchor = a;
            hasAnchor = true;
            dispersion = disp;
            lastQuorumAt = uint40(block.timestamp);
            if (regime == Regime.OPEN) lastOpenAnchorAt = uint40(block.timestamp);
        }
        uint256 divergence = hasSelf && hasAnchor ? _absDiff(selfTick, anchor) : 0;
        uint16 raw = RiskMath.raw(
            _r, block.timestamp - lastOpenAnchorAt, dispersion, divergence, block.timestamp - lastQuorumAt
        );
        riskBps = RiskMath.next(regime, riskBps, raw);
        emit QuorumComputed(q, anchor, dispersion, riskBps, n, chains);
        if (q && (force || _shouldSend())) _sendAnchor(n);
    }

    /// @dev SPEC §7.6 debounce: (moved ≥ minDelta OR risk bucket changed OR heartbeat) AND min interval.
    function _shouldSend() internal view returns (bool) {
        if (!sentOnce) return true;
        uint256 elapsed = block.timestamp - lastCallbackAt;
        if (elapsed < _q.minCallbackIntervalSeconds) return false;
        if (_absDiff(anchor, lastSentAnchor) >= _q.minAnchorDeltaTicks) return true;
        if (riskBps / _q.riskBucketBps != lastSentRisk / _q.riskBucketBps) return true;
        return elapsed >= _q.heartbeatSeconds;
    }

    /// @dev Fresh, enabled, non-SELF sources → weighted median + MAD + quorum test (SPEC §7.5).
    function _computeQuorum() internal view returns (bool q, int24 a, uint16 disp, uint8 n, uint8 nChains) {
        uint256 len = _sources.length;
        int24[] memory vals = new int24[](len);
        uint256[] memory ws = new uint256[](len);
        uint256[] memory chains = new uint256[](len);
        uint256 total;
        for (uint256 i; i < len; ++i) {
            uint256 w = _freshWeight(i);
            if (w == 0) continue;
            vals[n] = _state[i].ewma;
            ws[n] = w;
            total += w;
            ++n;
            uint256 cid = _sources[i].chainId;
            bool seen;
            for (uint256 j; j < nChains; ++j) {
                if (chains[j] == cid) seen = true;
            }
            if (!seen) chains[nChains++] = cid;
        }
        if (n == 0) return (false, 0, 0, 0, 0);
        assembly ("memory-safe") {
            mstore(vals, n)
            mstore(ws, n)
        }
        a = WitnessMath.weightedMedian(vals, ws);
        uint256 mad = WitnessMath.weightedMad(vals, ws, a);
        disp = mad > type(uint16).max ? type(uint16).max : uint16(mad);
        q = total >= uint256(_q.minQuorumWeight) * WitnessMath.WEIGHT_SCALE && nChains >= _q.minDistinctChains;
    }

    function _freshWeight(uint256 i) internal view returns (uint256) {
        WitnessSource storage s = _sources[i];
        if (!s.enabled || s.kind == SourceKind.SELF) return 0;
        uint40 seen = _state[i].lastSeen;
        if (seen == 0) return 0;
        uint256 maxAge = regime == Regime.OPEN ? s.maxAgeOpen : s.maxAgeClosed;
        uint256 weight = s.weight;
        bool issuer = s.kind == SourceKind.ISSUER_MINT || s.kind == SourceKind.ISSUER_REDEEM;
        if (issuer && regime == Regime.REOPEN_PENDING) weight *= _q.issuerOpenBoost;
        if (weight > type(uint16).max) weight = type(uint16).max;
        return WitnessMath.freshWeight(uint16(weight), block.timestamp - seen, maxAge);
    }

    function _findSource(LogRecord calldata log_) internal view returns (uint256) {
        uint256 len = _sources.length;
        for (uint256 i; i < len; ++i) {
            WitnessSource storage s = _sources[i];
            if (
                s.enabled && s.chainId == log_.chainId && s.emitter == log_.contractAddress && s.topic0 == log_.topic0
                    && (s.topic1 == REACTIVE_IGNORE || s.topic1 == log_.topic1)
            ) return i;
        }
        revert UnexpectedLog();
    }

    /// @dev Price from a witness log. Issuer: quote/shares ratio (notional = quote). v4 Swap: post-swap tick.
    function _decode(SourceKind kind, bytes calldata data) internal pure returns (bool, int24, uint256) {
        if (kind == SourceKind.ISSUER_MINT || kind == SourceKind.ISSUER_REDEEM) {
            (uint256 shares, uint256 quoteAmount) = abi.decode(data, (uint256, uint256));
            if (shares == 0 || quoteAmount == 0) return (false, 0, 0);
            return (true, PriceMath.tickFromRatio(quoteAmount, shares), quoteAmount);
        }
        if (kind == SourceKind.V4_SWAP || kind == SourceKind.SELF) {
            (,,,, int24 tick,) = abi.decode(data, (int128, int128, uint160, uint128, int24, uint24));
            return (true, tick, type(uint256).max); // notional filter not applied to pool swaps (ADR-017)
        }
        return (false, 0, 0); // V3_SWAP / ORACLE not wired in this build
    }

    // ---------------------------------------------------------------- internals: callbacks

    function _sendAnchor(uint8 n) internal {
        lastSentAnchor = anchor;
        lastSentRisk = riskBps;
        lastCallbackAt = uint40(block.timestamp);
        sentOnce = true;
        uint64 s = ++seq;
        _request(
            _g.onAnchor,
            abi.encodeWithSelector(
                INightShiftController.onAnchor.selector,
                address(0),
                poolId,
                s,
                anchor,
                riskBps,
                dispersion,
                n,
                uint40(block.timestamp)
            )
        );
        emit CallbackRequested(KIND_ANCHOR, s, anchor, riskBps, uint8(regime));
    }

    function _sendRegime(Regime r) internal {
        uint64 s = ++seq;
        _request(
            _g.onRegime,
            abi.encodeWithSelector(
                INightShiftController.onRegime.selector, address(0), poolId, s, uint8(r), uint40(block.timestamp)
            )
        );
        emit CallbackRequested(KIND_REGIME, s, anchor, riskBps, uint8(r));
    }

    function _sendReconcile(bool degraded) internal {
        uint64 s = ++seq;
        _request(
            _g.onReconcile,
            abi.encodeWithSelector(
                INightShiftController.onReconcile.selector,
                address(0),
                poolId,
                s,
                epochId,
                anchor,
                uint40(block.timestamp),
                degraded
            )
        );
        emit CallbackRequested(KIND_RECONCILE, s, anchor, riskBps, uint8(Regime.OPEN));
    }

    function _request(uint64 gasLimit, bytes memory payload) internal {
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: destChainId, recipient: controller, gasLimit: gasLimit, payload: payload
            })
        );
    }

    function _absDiff(int24 a, int24 b) internal pure returns (uint256) {
        int256 d = int256(a) - int256(b);
        return d >= 0 ? uint256(d) : uint256(-d);
    }
}
