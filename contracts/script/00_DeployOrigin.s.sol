// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {DemoToken} from "../src/mocks/DemoToken.sol";
import {MockIssuer} from "../src/mocks/MockIssuer.sol";
import {NightShiftConfig} from "./utils/NightShiftConfig.sol";
import {Deployments} from "./utils/Deployments.sol";

/// @title 00 — Origin chain (Ethereum Sepolia): demo tokens + MockIssuer (the issuer witness).
/// @notice `forge script script/00_DeployOrigin.s.sol --rpc-url $RPC_ETH_SEPOLIA --broadcast`
contract DeployOrigin is Script {
    using stdJson for string;

    function run() external {
        string memory cfg = NightShiftConfig.load("testnet");
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address me = vm.addr(pk);

        vm.startBroadcast(pk);
        DemoToken stock = new DemoToken("Demo Stock", "dSTOCK", uint8(cfg.readUint(".demo.stockDecimals")));
        DemoToken usd = new DemoToken("Demo USD", "dUSD", uint8(cfg.readUint(".demo.usdDecimals")));
        MockIssuer issuer = new MockIssuer(stock, usd, cfg.readUint(".demo.issuerPrice"));
        stock.setMinter(address(issuer), true);
        usd.mint(me, cfg.readUint(".demo.deployerUsdMint"));
        usd.approve(address(issuer), type(uint256).max);
        vm.stopBroadcast();

        string memory o = "origin";
        vm.serializeUint(o, "chainId", block.chainid);
        vm.serializeAddress(o, "dStock", address(stock));
        vm.serializeAddress(o, "dUsd", address(usd));
        string memory out = vm.serializeAddress(o, "mockIssuer", address(issuer));
        Deployments.write("testnet", "ethSepolia", out);
        console.log("MockIssuer", address(issuer));
    }
}
