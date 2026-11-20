// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {NightShiftVault} from "../src/vault/NightShiftVault.sol";
import {VaultFactory} from "../src/vault/VaultFactory.sol";
import {NightShiftConfig} from "./utils/NightShiftConfig.sol";
import {Deployments} from "./utils/Deployments.sol";

interface IControllerAdmin {
    function setFactory(address factory) external;
}

/// @title 08 — Destination (Base Sepolia): VaultFactory + three demo curator vaults (Conservative / Balanced /
///        Aggressive presets) with a seed deposit each. Vaults deploy liquidity on the next onAnchor callback.
/// @notice `forge script script/08_DeployVaults.s.sol --rpc-url $RPC_BASE_SEPOLIA --broadcast`
contract DeployVaults is Script {
    using stdJson for string;

    function _key(string memory cfg) internal view returns (PoolKey memory) {
        address stock = Deployments.addr("testnet", "destination", "dStock");
        address usd = Deployments.addr("testnet", "destination", "dUsd");
        (address c0, address c1) = stock < usd ? (stock, usd) : (usd, stock);
        return PoolKey(
            Currency.wrap(c0),
            Currency.wrap(c1),
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            NightShiftConfig.tickSpacing(cfg),
            IHooks(Deployments.addr("testnet", "destination", "hook"))
        );
    }

    function run() external {
        string memory cfg = NightShiftConfig.load("testnet");
        PoolKey memory key = _key(cfg);
        address ctrl = Deployments.addr("testnet", "destination", "controller");
        string[] memory presets = cfg.readStringArray(".demo.vaults.presets");
        string[] memory names = cfg.readStringArray(".demo.vaults.names");
        string[] memory symbols = cfg.readStringArray(".demo.vaults.symbols");
        bool stockIs0 = Currency.unwrap(key.currency0) == Deployments.addr("testnet", "destination", "dStock");
        uint256 seed0 = stockIs0 ? cfg.readUint(".demo.vaults.seedStock") : cfg.readUint(".demo.vaults.seedUsd");
        uint256 seed1 = stockIs0 ? cfg.readUint(".demo.vaults.seedUsd") : cfg.readUint(".demo.vaults.seedStock");
        address[] memory vaults = new address[](presets.length);

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        VaultFactory factory =
            new VaultFactory(IPoolManager(cfg.readAddress(".chains.destination.poolManager")), key, ctrl);
        IControllerAdmin(ctrl).setFactory(address(factory));
        for (uint256 i; i < presets.length; i++) {
            NightShiftVault v =
                NightShiftVault(factory.create(NightShiftConfig.mandate(cfg, presets[i]), names[i], symbols[i]));
            IERC20(Currency.unwrap(key.currency0)).approve(address(v), type(uint256).max);
            IERC20(Currency.unwrap(key.currency1)).approve(address(v), type(uint256).max);
            v.deposit(seed0, seed1, 0, vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY")));
            vaults[i] = address(v);
        }
        vm.stopBroadcast();

        string memory path = Deployments.path("testnet");
        vm.writeJson(string.concat('"', vm.toString(address(factory)), '"'), path, ".destination.factory");
        string memory arr = "[";
        for (uint256 i; i < vaults.length; i++) {
            arr = string.concat(arr, i == 0 ? "" : ",", '"', vm.toString(vaults[i]), '"');
        }
        vm.writeJson(string.concat(arr, "]"), path, ".destination.vaults");
        console.log("VaultFactory", address(factory));
    }
}
