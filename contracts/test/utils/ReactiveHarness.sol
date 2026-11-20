// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IReactive} from "@reactive/interfaces/IReactive.sol";
import {MockSystemContract} from "../../src/mocks/MockSystemContract.sol";

/// @title ReactiveHarness
/// @notice Simulates Reactive Network locally (SPEC §21.2) — and documents how the real loop works:
///         1. SYSTEM (0x8888…8888) is a MockSystemContract that records subscriptions and queues callbacks.
///         2. Origin-chain events are captured with vm.recordLogs and turned into LogRecords.
///         3. The harness calls react() as SYSTEM.
///         4. Queued callbacks are relayed like the callback proxy does: the first 32-byte argument is overwritten
///            with the reactive contract's address, then the recipient is called from the proxy address.
abstract contract ReactiveHarness is Test {
    address internal constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    MockSystemContract internal sys;

    function _etchSystem() internal {
        vm.etch(SYSTEM_ADDR, type(MockSystemContract).runtimeCode);
        sys = MockSystemContract(payable(SYSTEM_ADDR));
    }

    /// @notice First log from `emitter` with `topic0` among recorded logs, as a LogRecord on virtual `chainId`.
    function _capture(Vm.Log[] memory logs, address emitter, bytes32 topic0, uint256 chainId)
        internal
        view
        returns (IReactive.LogRecord memory r)
    {
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != emitter || logs[i].topics[0] != topic0) continue;
            r.chainId = chainId;
            r.contractAddress = emitter;
            r.topic0 = uint256(logs[i].topics[0]);
            if (logs[i].topics.length > 1) r.topic1 = uint256(logs[i].topics[1]);
            if (logs[i].topics.length > 2) r.topic2 = uint256(logs[i].topics[2]);
            if (logs[i].topics.length > 3) r.topic3 = uint256(logs[i].topics[3]);
            r.data = logs[i].data;
            r.blockNumber = block.number;
            return r;
        }
        revert("ReactiveHarness: log not found");
    }

    /// @notice Deliver every queued callback as the callback proxy would; returns how many were relayed.
    function _relayCallbacks(address callbackProxy) internal returns (uint256 n) {
        n = sys.queueLength();
        for (uint256 i; i < n; i++) {
            MockSystemContract.Queued memory q = sys.queuedAt(i);
            bytes memory payload = q.config.payload;
            address requester = q.requester;
            assembly ("memory-safe") {
                // payload = selector(4) | arg0(32) | ... → arg0 starts at payload+32+4
                mstore(add(payload, 36), requester)
            }
            vm.prank(callbackProxy);
            (bool ok, bytes memory ret) = q.config.recipient.call{gas: q.config.gasLimit}(payload);
            if (!ok) {
                assembly ("memory-safe") {
                    revert(add(ret, 32), mload(ret))
                }
            }
        }
        sys.clearQueue();
    }
}
