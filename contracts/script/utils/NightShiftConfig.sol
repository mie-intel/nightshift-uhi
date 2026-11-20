// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {PoolConfig, RiskParams, QuorumParams, GasLimits} from "../../src/libraries/Types.sol";

/// @title NightShiftConfig
/// @notice Reads tunable parameters from `contracts/config/{network}.json` (rule: params never hard-coded).
///         Shared by deploy scripts and tests.
library NightShiftConfig {
    using stdJson for string;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Raw JSON for `network` ("testnet" | "mainnet"). Path relative to the Foundry project root.
    function load(string memory network) internal view returns (string memory) {
        return vm.readFile(string.concat(vm.projectRoot(), "/config/", network, ".json"));
    }

    /// @notice Hook fee policy from the `fee` section.
    function poolConfig(string memory json) internal pure returns (PoolConfig memory c) {
        c.baseOpen = uint24(json.readUint(".fee.baseOpen"));
        c.baseClosed = uint24(json.readUint(".fee.baseClosed"));
        c.driftSlopeOpen = uint24(json.readUint(".fee.driftSlopeOpen"));
        c.captureShare = uint16(json.readUint(".fee.captureShare"));
        c.riskFeeMax = uint24(json.readUint(".fee.riskFeeMax"));
        c.driftSlope = uint24(json.readUint(".fee.driftSlope"));
        c.driftMax = uint24(json.readUint(".fee.driftMax"));
        c.maxFeeClosed = uint24(json.readUint(".fee.maxFeeClosed"));
        c.reopenSurcharge = uint24(json.readUint(".fee.reopenSurcharge"));
        c.deadbandTicks = uint24(json.readUint(".fee.deadbandTicks"));
        c.maxAwayMove = uint24(json.readUint(".fee.maxAwayMove"));
        c.overshootCap = uint24(json.readUint(".fee.overshootCap"));
        c.anchorMaxAgeOpen = uint32(json.readUint(".fee.anchorMaxAgeOpen"));
        c.anchorMaxAgeClosed = uint32(json.readUint(".fee.anchorMaxAgeClosed"));
    }

    /// @notice Gap Risk Score params from the `risk` section.
    function riskParams(string memory json) internal pure returns (RiskParams memory r) {
        r.timeFullSeconds = uint32(json.readUint(".risk.timeFullSeconds"));
        r.dispersionFullTicks = uint24(json.readUint(".risk.dispersionFullTicks"));
        r.divergenceFullTicks = uint24(json.readUint(".risk.divergenceFullTicks"));
        r.stalenessFullSeconds = uint32(json.readUint(".risk.stalenessFullSeconds"));
        r.weightTime = uint16(json.readUint(".risk.weightTime"));
        r.weightDispersion = uint16(json.readUint(".risk.weightDispersion"));
        r.weightDivergence = uint16(json.readUint(".risk.weightDivergence"));
        r.weightStaleness = uint16(json.readUint(".risk.weightStaleness"));
    }

    /// @notice Quorum + debounce + reopen params from `quorum` and `debounce`.
    function quorumParams(string memory json) internal pure returns (QuorumParams memory q) {
        q.minQuorumWeight = uint16(json.readUint(".quorum.minQuorumWeight"));
        q.minDistinctChains = uint8(json.readUint(".quorum.minDistinctChains"));
        q.maxJumpTicks = uint24(json.readUint(".quorum.maxJumpTicks"));
        q.halfLifeSeconds = uint32(json.readUint(".quorum.halfLifeSeconds"));
        q.minAnchorDeltaTicks = uint24(json.readUint(".quorum.minAnchorDeltaTicks"));
        q.riskBucketBps = uint16(json.readUint(".quorum.riskBucketBps"));
        q.heartbeatSeconds = uint32(json.readUint(".debounce.heartbeatSeconds"));
        q.minCallbackIntervalSeconds = uint32(json.readUint(".debounce.minCallbackIntervalSeconds"));
        q.openWindowSeconds = uint32(json.readUint(".quorum.openWindowSeconds"));
        q.reconcileTimeoutSeconds = uint32(json.readUint(".quorum.reconcileTimeoutSeconds"));
        q.issuerOpenBoost = uint8(json.readUint(".quorum.issuerOpenBoost"));
    }

    /// @notice Callback gas limits.
    function gasLimits(string memory json) internal pure returns (GasLimits memory g) {
        g.onAnchor = uint64(json.readUint(".gasLimits.onAnchor"));
        g.onRegime = uint64(json.readUint(".gasLimits.onRegime"));
        g.onReconcile = uint64(json.readUint(".gasLimits.onReconcile"));
    }

    /// @notice Cron topic0 for the reactive subscription.
    function cronTopic(string memory json) internal pure returns (uint256) {
        return uint256(json.readBytes32(".cron.topic0"));
    }

    /// @notice Pool tick spacing.
    function tickSpacing(string memory json) internal pure returns (int24) {
        return int24(int256(json.readUint(".pool.tickSpacing")));
    }

    /// @notice onAnchor callback gas limit.
    function anchorGasLimit(string memory json) internal pure returns (uint64) {
        return uint64(json.readUint(".gasLimits.onAnchor"));
    }
}
