// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {NightShiftReactive} from "../src/reactive/NightShiftReactive.sol";
import {NightShiftConfig} from "./utils/NightShiftConfig.sol";
import {Deployments} from "./utils/Deployments.sol";

/// @title 02 — Reactive Network (Lasna): NightShiftReactive, funded with lREACT. Controller/subscription wired in 04.
/// @notice `FOUNDRY_PROFILE=reactive forge script script/02_DeployReactive.s.sol --rpc-url $RPC_LASNA --broadcast`
contract DeployReactive is Script {
    using stdJson for string;

    function run() external {
        string memory cfg = NightShiftConfig.load("testnet");
        uint256 pk = vm.envUint("REACTIVE_PRIVATE_KEY");

        vm.startBroadcast(pk);
        NightShiftReactive rx = new NightShiftReactive{value: cfg.readUint(".funding.reactiveWei")}(
            cfg.readUint(".chains.unichainSepolia.chainId"),
            Deployments.b32("testnet", "unichainSepolia", "poolId"),
            cfg.readUint(".chains.ethSepolia.chainId"),
            Deployments.addr("testnet", "ethSepolia", "mockIssuer"),
            Deployments.flag("testnet", "unichainSepolia", "invert"),
            0, // same decimals on every chain (config.demo)
            NightShiftConfig.anchorGasLimit(cfg)
        );
        vm.stopBroadcast();

        string memory o = "lasna";
        vm.serializeUint(o, "chainId", block.chainid);
        string memory out = vm.serializeAddress(o, "reactive", address(rx));
        Deployments.write("testnet", "lasna", out);
        console.log("NightShiftReactive", address(rx));
    }
}
