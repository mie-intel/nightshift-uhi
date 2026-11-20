// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {NightShiftHook} from "../src/hook/NightShiftHook.sol";
import {DemoToken} from "../src/mocks/DemoToken.sol";
import {PriceMath} from "../src/libraries/PriceMath.sol";
import {PoolConfig} from "../src/libraries/Types.sol";
import {NightShiftConfig} from "./utils/NightShiftConfig.sol";
import {Deployments} from "./utils/Deployments.sol";

/// @title 01 — Destination chain (Base Sepolia; set in config.chains.destination): demo tokens, mined hook, dynamic-fee pool at the issuer price,
///        test routers, seed liquidity.
/// @notice `forge script script/01_DeployDestination.s.sol --rpc-url $RPC_BASE_SEPOLIA --broadcast`
contract DeployDestination is Script {
    using stdJson for string;

    uint160 internal constant FLAGS =
        Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG;

    struct Ctx {
        string cfg;
        address me;
        IPoolManager pm;
        PoolConfig pc;
        DemoToken stock;
        DemoToken usd;
        NightShiftHook hook;
        PoolSwapTest swapRouter;
        PoolModifyLiquidityTest lpRouter;
        PoolKey key;
        PoolKey siblingKey;
        bool invert;
        int24 initTick;
    }

    function run() external {
        Ctx memory c;
        c.cfg = NightShiftConfig.load("testnet");
        c.pc = NightShiftConfig.poolConfig(c.cfg);
        c.pm = IPoolManager(c.cfg.readAddress(".chains.destination.poolManager"));
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        c.me = vm.addr(pk);

        bytes memory args = abi.encode(c.pm, c.pc, NightShiftConfig.riskParams(c.cfg), c.me);
        (address predicted, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, FLAGS, type(NightShiftHook).creationCode, args);

        vm.startBroadcast(pk);
        c.stock = new DemoToken("Demo Stock", "dSTOCK", uint8(c.cfg.readUint(".demo.stockDecimals")));
        c.usd = new DemoToken("Demo USD", "dUSD", uint8(c.cfg.readUint(".demo.usdDecimals")));
        c.hook = new NightShiftHook{salt: salt}(c.pm, c.pc, NightShiftConfig.riskParams(c.cfg), c.me);
        require(address(c.hook) == predicted, "hook address mismatch");
        c.swapRouter = new PoolSwapTest(c.pm);
        c.lpRouter = new PoolModifyLiquidityTest(c.pm);
        _initPoolAndSeed(c);
        vm.stopBroadcast();

        _write(c);
    }

    function _initPoolAndSeed(Ctx memory c) internal {
        // dest tick = log(currency1 per currency0). Issuer quotes dUSD per dSTOCK, so invert iff dSTOCK is currency1.
        c.invert = address(c.stock) > address(c.usd);
        (Currency c0, Currency c1) = c.invert
            ? (Currency.wrap(address(c.usd)), Currency.wrap(address(c.stock)))
            : (Currency.wrap(address(c.stock)), Currency.wrap(address(c.usd)));
        c.initTick =
            PriceMath.normalize(PriceMath.tickFromRatio(c.cfg.readUint(".demo.issuerPrice"), 1e18), c.invert, 0);
        int24 spacing = NightShiftConfig.tickSpacing(c.cfg);
        c.key = PoolKey(c0, c1, LPFeeLibrary.DYNAMIC_FEE_FLAG, spacing, IHooks(address(c.hook)));
        c.pm.initialize(c.key, TickMath.getSqrtPriceAtTick(c.initTick));

        c.stock.mint(c.me, c.cfg.readUint(".demo.deployerStockMint"));
        c.usd.mint(c.me, c.cfg.readUint(".demo.deployerUsdMint"));
        c.stock.approve(address(c.lpRouter), type(uint256).max);
        c.usd.approve(address(c.lpRouter), type(uint256).max);
        c.stock.approve(address(c.swapRouter), type(uint256).max);
        c.usd.approve(address(c.swapRouter), type(uint256).max);

        int24 half = int24(int256(c.cfg.readUint(".demo.liquidityHalfWidthTicks")));
        int24 lower = _floor(c.initTick - half, spacing);
        int24 upper = _floor(c.initTick + half, spacing) + spacing;
        ModifyLiquidityParams memory lp =
            ModifyLiquidityParams(lower, upper, int256(c.cfg.readUint(".demo.liquidityDelta")), 0);
        c.lpRouter.modifyLiquidity(c.key, lp, "");

        // Sibling pool B: a plain v4 pool (no hook) for the same pair — a separate market that Reactive witnesses.
        c.siblingKey = PoolKey(c0, c1, uint24(c.cfg.readUint(".demo.siblingFee")), spacing, IHooks(address(0)));
        c.pm.initialize(c.siblingKey, TickMath.getSqrtPriceAtTick(c.initTick));
        c.lpRouter.modifyLiquidity(c.siblingKey, lp, "");
    }

    function _floor(int24 t, int24 spacing) internal pure returns (int24) {
        int24 q = t / spacing;
        if (t < 0 && t % spacing != 0) q--;
        return q * spacing;
    }

    function _write(Ctx memory c) internal {
        string memory o = "dest";
        vm.serializeUint(o, "chainId", block.chainid);
        vm.serializeUint(o, "deployBlock", block.number); // lower bound for dashboard event scans
        vm.serializeAddress(o, "poolManager", address(c.pm));
        vm.serializeAddress(o, "dStock", address(c.stock));
        vm.serializeAddress(o, "dUsd", address(c.usd));
        vm.serializeAddress(o, "hook", address(c.hook));
        vm.serializeAddress(o, "swapRouter", address(c.swapRouter));
        vm.serializeAddress(o, "liquidityRouter", address(c.lpRouter));
        vm.serializeBool(o, "invert", c.invert);
        vm.serializeInt(o, "initTick", c.initTick);
        vm.serializeAddress(o, "controller", address(0)); // set by 03
        vm.serializeAddress(o, "faucet", address(0)); // set by 06
        vm.serializeAddress(o, "factory", address(0)); // set by 08
        vm.serializeAddress(o, "vaults", new address[](0)); // set by 08
        vm.serializeUint(o, "siblingFee", c.siblingKey.fee);
        vm.serializeBytes32(o, "siblingPoolId", PoolId.unwrap(c.siblingKey.toId()));
        string memory out = vm.serializeBytes32(o, "poolId", PoolId.unwrap(c.key.toId()));
        Deployments.write("testnet", "destination", out);
        console.log("hook", address(c.hook));
        console.logBytes32(PoolId.unwrap(c.key.toId()));
    }
}
