// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ISystemContract} from "@reactive/interfaces/ISystemContract.sol";

/// @title MockSystemContract
/// @notice Local stand-in for Reactive's SYSTEM (0x8888…8888) used by the ReactiveHarness (SPEC §21.2).
///         Records subscriptions and queues requested callbacks; never deployed to a real network.
contract MockSystemContract {
    /// @notice A recorded subscription.
    struct Sub {
        address subscriber;
        uint256 chainId;
        address emitter;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
    }

    /// @notice A queued callback request.
    struct Queued {
        address requester;
        ISystemContract.CallbackConfiguration_V_1_0 config;
    }

    Sub[] internal _subs;
    Queued[] internal _queue;
    /// @notice Debt per contract (settable by tests).
    mapping(address => uint256) public debt;

    /// @notice Record a subscription.
    function subscribe(uint256 chainId, address emitter, uint256 t0, uint256 t1, uint256 t2, uint256 t3) external {
        _subs.push(Sub(msg.sender, chainId, emitter, t0, t1, t2, t3));
    }

    /// @notice Unsubscriptions recorded (count only).
    uint256 public unsubCount;

    /// @notice Record an unsubscription.
    function unsubscribe(uint256, address, uint256, uint256, uint256, uint256) external {
        unsubCount++;
    }

    /// @notice Queue a callback request.
    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory config) external {
        _queue.push(Queued(msg.sender, config));
    }

    /// @notice Test helper: set a contract's debt.
    function setDebt(address c, uint256 amount) external {
        debt[c] = amount;
    }

    /// @notice Accept debt payments.
    receive() external payable {
        debt[msg.sender] = 0;
    }

    /// @notice Number of subscriptions recorded.
    function subCount() external view returns (uint256) {
        return _subs.length;
    }

    /// @notice Subscription `i`.
    function subAt(uint256 i) external view returns (Sub memory) {
        return _subs[i];
    }

    /// @notice Number of queued callbacks.
    function queueLength() external view returns (uint256) {
        return _queue.length;
    }

    /// @notice Queued callback `i`.
    function queuedAt(uint256 i) external view returns (Queued memory) {
        return _queue[i];
    }

    /// @notice Drop all queued callbacks (after relaying).
    function clearQueue() external {
        delete _queue;
    }
}
