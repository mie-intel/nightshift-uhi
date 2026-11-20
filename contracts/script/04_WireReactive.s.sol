// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {NightShiftReactive} from "../src/reactive/NightShiftReactive.sol";
import {SourceKind, WitnessSource} from "../src/libraries/Types.sol";
import {NightShiftConfig} from "./utils/NightShiftConfig.sol";
import {Deployments} from "./utils/Deployments.sol";

/// @title 04 — Reactive Network (Lasna): set the Controller, add the witness sources (each subscribes), subscribe Cron.
///        Sources: issuer Minted + Redeemed (Ethereum Sepolia, w5) · sibling v4 pool (Base Sepolia, w2) ·
///        the destination pool's own swaps (SELF, w0 — divergence only).
/// @notice `FOUNDRY_PROFILE=reactive forge script script/04_WireReactive.s.sol --rpc-url $RPC_LASNA --broadcast`
contract WireReactive is Script {
    using stdJson for string;

    uint256 internal constant REACTIVE_IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

    function _src(string memory cfg, uint256 chainId, address emitter, uint256 t0, uint256 t1, SourceKind k, uint16 w)
        internal
        pure
        returns (WitnessSource memory s)
    {
        s.chainId = chainId;
        s.emitter = emitter;
        s.topic0 = t0;
        s.topic1 = t1;
        s.kind = k;
        s.weight = w;
        s.maxAgeOpen = uint32(cfg.readUint(".witness.maxAgeOpenSeconds"));
        s.maxAgeClosed = uint32(cfg.readUint(".witness.maxAgeClosedSeconds"));
        s.enabled = true;
    }

    function _issuer(string memory cfg, uint256 topic0, SourceKind kind)
        internal
        view
        returns (WitnessSource memory s)
    {
        s = _src(
            cfg,
            cfg.readUint(".chains.ethSepolia.chainId"),
            Deployments.addr("testnet", "ethSepolia", "mockIssuer"),
            topic0,
            REACTIVE_IGNORE,
            kind,
            uint16(cfg.readUint(".sourceWeights.issuerMintRedeem"))
        );
        // issuer quotes dUSD per dSTOCK; the destination tick is inverted iff dSTOCK is currency1 there
        s.invert = Deployments.flag("testnet", "destination", "invert");
    }

    /// @dev v4 pool on the destination chain filtered by pool id (same tokens/order as our pool → same tick space).
    function _pool(string memory cfg, NightShiftReactive rx, string memory idKey, SourceKind kind, uint16 weight)
        internal
        view
        returns (WitnessSource memory)
    {
        return _src(
            cfg,
            cfg.readUint(".chains.destination.chainId"),
            cfg.readAddress(".chains.destination.poolManager"),
            rx.V4_SWAP_TOPIC0(),
            uint256(Deployments.b32("testnet", "destination", idKey)),
            kind,
            weight
        );
    }

    function run() external {
        string memory cfg = NightShiftConfig.load("testnet");
        NightShiftReactive rx = NightShiftReactive(payable(Deployments.addr("testnet", "lasna", "reactive")));
        address ctrl = Deployments.addr("testnet", "destination", "controller");
        require(ctrl != address(0), "run 03 first");

        WitnessSource[4] memory srcs = [
            _issuer(cfg, rx.MINTED_TOPIC0(), SourceKind.ISSUER_MINT),
            _issuer(cfg, rx.REDEEMED_TOPIC0(), SourceKind.ISSUER_REDEEM),
            _pool(cfg, rx, "siblingPoolId", SourceKind.V4_SWAP, uint16(cfg.readUint(".sourceWeights.v4SwapOther"))),
            _pool(cfg, rx, "poolId", SourceKind.SELF, 0)
        ];

        vm.startBroadcast(vm.envUint("REACTIVE_PRIVATE_KEY"));
        rx.setController(ctrl);
        for (uint256 i; i < srcs.length; i++) {
            rx.addSource(srcs[i]);
        }
        rx.subscribeCron();
        vm.stopBroadcast();
        console.log("reactive", address(rx), "-> controller", ctrl);
    }
}
