// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AbstractReactive} from "@reactive/base/AbstractReactive.sol";
import {ISystemContract} from "@reactive/interfaces/ISystemContract.sol";

import {INightShiftController} from "../interfaces/INightShiftController.sol";
import {PriceMath} from "../libraries/PriceMath.sol";

/// @title NightShiftReactive (v0 — walking skeleton for Gate 1)
/// @notice Runs on Reactive Network. Subscribes to the issuer's `Minted` event on the origin chain, converts the
///         execution price into a destination-pool tick, and requests an `onAnchor` callback to the destination
///         Controller — pushing price state into the pool between trades (README §7, §13.2).
/// @dev v0 has a single witness (no quorum). Phase 6 replaces this with the full Witness Quorum + risk + Cron regime.
contract NightShiftReactive is AbstractReactive {
    /// @notice topic0 of `MockIssuer.Minted(address indexed to, uint256 shares, uint256 quoteAmount)`.
    uint256 public constant MINTED_TOPIC0 = uint256(keccak256("Minted(address,uint256,uint256)"));

    /// @notice Admin (subscribe, set controller).
    address public immutable owner;
    /// @notice Destination chain id (e.g. Base Sepolia 84532).
    uint256 public immutable destChainId;
    /// @notice Destination pool id.
    bytes32 public immutable poolId;
    /// @notice Origin chain of the issuer witness (e.g. Ethereum Sepolia 11155111).
    uint256 public immutable issuerChainId;
    /// @notice Issuer contract on the origin chain.
    address public immutable issuer;
    /// @notice Source token order reversed vs destination pool.
    bool public immutable invert;
    /// @notice Decimals/quote adjustment into destination tick space.
    int24 public immutable offsetTicks;
    /// @notice Gas limit for the onAnchor callback (>= 100 000).
    uint64 public immutable anchorGasLimit;

    /// @notice Destination Controller.
    address public controller;
    /// @notice Monotonic callback sequence for the pool.
    uint64 public seq;
    /// @notice Last anchor sent.
    int24 public lastAnchor;

    /// @notice Caller is not the owner.
    error NotOwner();
    /// @notice Controller not configured yet.
    error ControllerNotSet();
    /// @notice react() received a log we did not subscribe to.
    error UnexpectedLog();

    /// @notice Controller configured.
    event ControllerSet(address controller);
    /// @notice Subscribed to the issuer witness.
    event Subscribed(uint256 chainId, address emitter, uint256 topic0);
    /// @notice A witness observation was processed (README §14.4).
    event WitnessObserved(uint256 indexed chainId, address indexed emitter, int24 destTick, uint256 blockNumber);
    /// @notice A callback was requested (README §14.4).
    event CallbackRequested(uint256 indexed destChainId, address indexed controller, uint64 seq, int24 anchorTick);

    constructor(
        uint256 destChainId_,
        bytes32 poolId_,
        uint256 issuerChainId_,
        address issuer_,
        bool invert_,
        int24 offsetTicks_,
        uint64 anchorGasLimit_
    ) payable {
        owner = msg.sender;
        destChainId = destChainId_;
        poolId = poolId_;
        issuerChainId = issuerChainId_;
        issuer = issuer_;
        invert = invert_;
        offsetTicks = offsetTicks_;
        anchorGasLimit = anchorGasLimit_;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Set the destination Controller (deployed after this contract, since it pins our address).
    function setController(address controller_) external onlyOwner {
        controller = controller_;
        emit ControllerSet(controller_);
    }

    /// @notice Subscribe to the issuer's `Minted` events on the origin chain.
    function subscribe() external onlyOwner {
        SYSTEM.subscribe(issuerChainId, issuer, MINTED_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
        emit Subscribed(issuerChainId, issuer, MINTED_TOPIC0);
    }

    /// @notice Handle a subscribed log: issuer mint → destination tick → onAnchor callback.
    function react(LogRecord calldata log_) external onlySystem {
        if (log_.chainId != issuerChainId || log_.contractAddress != issuer || log_.topic0 != MINTED_TOPIC0) {
            revert UnexpectedLog();
        }
        address controller_ = controller;
        if (controller_ == address(0)) revert ControllerNotSet();

        (uint256 shares, uint256 quoteAmount) = abi.decode(log_.data, (uint256, uint256));
        int24 tick = PriceMath.normalize(PriceMath.tickFromRatio(quoteAmount, shares), invert, offsetTicks);
        emit WitnessObserved(log_.chainId, log_.contractAddress, tick, log_.blockNumber);

        uint64 s = ++seq;
        lastAnchor = tick;
        bytes memory payload = abi.encodeWithSelector(
            INightShiftController.onAnchor.selector,
            address(0), // overwritten by the callback proxy with this contract's address
            poolId,
            s,
            tick,
            uint16(0), // risk (Phase 6)
            uint16(0), // dispersion (Phase 6)
            uint8(1), // sources in quorum
            uint40(block.timestamp)
        );
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: destChainId, recipient: controller_, gasLimit: anchorGasLimit, payload: payload
            })
        );
        emit CallbackRequested(destChainId, controller_, s, tick);
    }

    /// @notice Repay any outstanding debt to SYSTEM from this contract's balance (debt blocks execution).
    function coverDebt() external {
        _coverDebt();
    }
}
