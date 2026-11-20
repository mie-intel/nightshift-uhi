// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {PriceMath} from "../src/libraries/PriceMath.sol";
import {NightShiftConfig} from "./utils/NightShiftConfig.sol";
import {Deployments} from "./utils/Deployments.sol";

/// @title 07 — Destination (Base Sepolia): trade the sibling pool (a separate market) to PRICE (raw dUSD per 1e18
///        dSTOCK, e.g. 104000000 = 104 dUSD). Reactive witnesses its Swap — the second chain of the quorum.
/// @notice `PRICE=104000000 forge script script/07_MoveSibling.s.sol --rpc-url $RPC_BASE_SEPOLIA --broadcast`
contract MoveSibling is Script {
    using stdJson for string;

    function run() external {
        string memory cfg = NightShiftConfig.load("testnet");
        address stock = Deployments.addr("testnet", "destination", "dStock");
        address usd = Deployments.addr("testnet", "destination", "dUsd");
        bool invert = Deployments.flag("testnet", "destination", "invert");
        (address c0, address c1) = invert ? (usd, stock) : (stock, usd);
        PoolKey memory key = PoolKey(
            Currency.wrap(c0),
            Currency.wrap(c1),
            uint24(cfg.readUint(".demo.siblingFee")),
            NightShiftConfig.tickSpacing(cfg),
            IHooks(address(0))
        );
        int24 target = PriceMath.normalize(PriceMath.tickFromRatio(vm.envUint("PRICE"), 1e18), invert, 0);
        IPoolManager pm = IPoolManager(cfg.readAddress(".chains.destination.poolManager"));
        (, int24 tick,,) = StateLibrary.getSlot0(pm, key.toId());
        if (tick == target) return;
        bool zeroForOne = target < tick;

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        PoolSwapTest(Deployments.addr("testnet", "destination", "swapRouter"))
            .swap(
                key,
                SwapParams(zeroForOne, -1e30, TickMath.getSqrtPriceAtTick(target)),
                PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
                ""
            );
        vm.stopBroadcast();
        console.log("sibling tick ->");
        console.logInt(target);
    }
}
