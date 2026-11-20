// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {MockIssuer} from "../src/mocks/MockIssuer.sol";
import {NightShiftConfig} from "./utils/NightShiftConfig.sol";
import {Deployments} from "./utils/Deployments.sol";

/// @title 05 — Origin (Ethereum Sepolia): set the issuer price (PRICE, or current price moved by MOVE_BPS) and mint 1 share.
///        The `Minted` event is what Reactive witnesses → onAnchor callback on the destination chain (Base Sepolia).
/// @notice `MOVE_BPS=200 forge script script/05_TriggerIssuerMint.s.sol --rpc-url $RPC_ETH_SEPOLIA --broadcast`
contract TriggerIssuerMint is Script {
    using stdJson for string;

    function run() external {
        string memory cfg = NightShiftConfig.load("testnet");
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        MockIssuer issuer = MockIssuer(Deployments.addr("testnet", "ethSepolia", "mockIssuer"));
        // PRICE (raw dUSD per share) wins; else move the CURRENT on-chain price by MOVE_BPS (default +200 = +2%)
        uint256 price = vm.envOr("PRICE", uint256(0));
        if (price == 0) {
            price = uint256(int256(issuer.price()) * (10_000 + vm.envOr("MOVE_BPS", int256(200))) / 10_000);
        }
        uint256 oneShare = 10 ** cfg.readUint(".demo.stockDecimals");

        vm.startBroadcast(pk);
        issuer.setPrice(price);
        issuer.mint(oneShare);
        vm.stopBroadcast();
        console.log("issuer price (raw dUSD per share)", price);
    }
}
