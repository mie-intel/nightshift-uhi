// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// @title Deployments
/// @notice Read/write `deployments/{network}.json` (one object per chain section). Consumed by recorder + app.
library Deployments {
    using stdJson for string;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Absolute path of the deployments file for `network`.
    function path(string memory network) internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/../deployments/", network, ".json");
    }

    /// @notice Replace section `section` (e.g. "ethSepolia") with the serialized object `obj`.
    function write(string memory network, string memory section, string memory obj) internal {
        vm.writeJson(obj, path(network), string.concat(".", section));
    }

    /// @notice Read an address `section.key`.
    function addr(string memory network, string memory section, string memory key) internal view returns (address) {
        return vm.readFile(path(network)).readAddress(string.concat(".", section, ".", key));
    }

    /// @notice Read a bytes32 `section.key`.
    function b32(string memory network, string memory section, string memory key) internal view returns (bytes32) {
        return vm.readFile(path(network)).readBytes32(string.concat(".", section, ".", key));
    }

    /// @notice Read a bool `section.key`.
    function flag(string memory network, string memory section, string memory key) internal view returns (bool) {
        return vm.readFile(path(network)).readBool(string.concat(".", section, ".", key));
    }
}
