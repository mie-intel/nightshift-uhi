// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {DemoToken} from "../src/mocks/DemoToken.sol";
import {DemoFaucet} from "../src/mocks/DemoFaucet.sol";
import {NightShiftConfig} from "./utils/NightShiftConfig.sol";
import {Deployments} from "./utils/Deployments.sol";

/// @title 06 — Destination (Base Sepolia): public demo-token faucet so anyone can try swaps from the dashboard.
/// @notice `forge script script/06_DeployFaucet.s.sol --rpc-url $RPC_BASE_SEPOLIA --broadcast`
contract DeployFaucet is Script {
    using stdJson for string;

    function run() external {
        string memory cfg = NightShiftConfig.load("testnet");
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        DemoToken stock = DemoToken(Deployments.addr("testnet", "destination", "dStock"));
        DemoToken usd = DemoToken(Deployments.addr("testnet", "destination", "dUsd"));

        vm.startBroadcast(pk);
        DemoFaucet faucet = new DemoFaucet(
            stock,
            usd,
            cfg.readUint(".demo.faucetStock"),
            cfg.readUint(".demo.faucetUsd"),
            cfg.readUint(".demo.faucetCooldownSeconds")
        );
        stock.setMinter(address(faucet), true);
        usd.setMinter(address(faucet), true);
        vm.stopBroadcast();

        vm.writeJson(
            string.concat('"', vm.toString(address(faucet)), '"'), Deployments.path("testnet"), ".destination.faucet"
        );
        console.log("DemoFaucet", address(faucet));
    }
}
