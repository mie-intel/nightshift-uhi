// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";

import {NightShiftReactive} from "../src/reactive/NightShiftReactive.sol";
import {Deployments} from "./utils/Deployments.sol";

/// @title 04 — Reactive Network (Lasna): point the reactive contract at the Controller and subscribe to the issuer.
/// @notice `FOUNDRY_PROFILE=reactive forge script script/04_WireReactive.s.sol --rpc-url $RPC_LASNA --broadcast`
contract WireReactive is Script {
    function run() external {
        uint256 pk = vm.envUint("REACTIVE_PRIVATE_KEY");
        NightShiftReactive rx = NightShiftReactive(payable(Deployments.addr("testnet", "lasna", "reactive")));
        address ctrl = Deployments.addr("testnet", "unichainSepolia", "controller");
        require(ctrl != address(0), "run 03 first");

        vm.startBroadcast(pk);
        rx.setController(ctrl);
        rx.subscribe();
        vm.stopBroadcast();
        console.log("reactive", address(rx), "-> controller", ctrl);
    }
}
