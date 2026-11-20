// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {NightShiftController} from "../src/controller/NightShiftController.sol";
import {INightShiftHook} from "../src/interfaces/INightShiftHook.sol";
import {NightShiftConfig} from "./utils/NightShiftConfig.sol";
import {Deployments} from "./utils/Deployments.sol";

interface IHookAdmin {
    function initController(address controller) external;
}

/// @title 03 — Destination (Base Sepolia): Controller pinned to (callback proxy, reactive), funded for callbacks;
///        hook accepts only this Controller from now on.
/// @notice `forge script script/03_DeployController.s.sol --rpc-url $RPC_BASE_SEPOLIA --broadcast`
contract DeployController is Script {
    using stdJson for string;

    function run() external {
        string memory cfg = NightShiftConfig.load("testnet");
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address hook = Deployments.addr("testnet", "destination", "hook");
        address reactive = Deployments.addr("testnet", "lasna", "reactive");

        vm.startBroadcast(pk);
        NightShiftController ctrl = new NightShiftController{value: cfg.readUint(".funding.controllerWei")}(
            cfg.readAddress(".chains.destination.callbackProxy"),
            reactive,
            INightShiftHook(hook),
            cfg.readUint(".quorum.reconcileTimeoutSeconds")
        );
        IHookAdmin(hook).initController(address(ctrl));
        vm.stopBroadcast();

        // 01 wrote a placeholder `controller` key; replace just that value (JSON string)
        vm.writeJson(
            string.concat('"', vm.toString(address(ctrl)), '"'), Deployments.path("testnet"), ".destination.controller"
        );
        console.log("NightShiftController", address(ctrl));
    }
}
