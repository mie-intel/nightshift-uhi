// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {PoolConfig} from "../../src/libraries/Types.sol";

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

    /// @notice Pool tick spacing.
    function tickSpacing(string memory json) internal pure returns (int24) {
        return int24(int256(json.readUint(".pool.tickSpacing")));
    }

    /// @notice onAnchor callback gas limit.
    function anchorGasLimit(string memory json) internal pure returns (uint64) {
        return uint64(json.readUint(".gasLimits.onAnchor"));
    }
}
