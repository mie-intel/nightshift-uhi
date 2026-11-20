// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {stdJson} from "forge-std/StdJson.sol";
import {IReactive} from "@reactive/interfaces/IReactive.sol";

import {ReactiveHarness} from "./ReactiveHarness.sol";
import {NightShiftReactive} from "../../src/reactive/NightShiftReactive.sol";
import {MockSystemContract} from "../../src/mocks/MockSystemContract.sol";
import {NyseCalendar} from "../../src/libraries/NyseCalendar.sol";
import {GasLimits, QuorumParams, RiskParams, SourceKind, WitnessSource} from "../../src/libraries/Types.sol";
import {NightShiftConfig} from "../../script/utils/NightShiftConfig.sol";

/// @notice NightShiftReactive wired with three witnesses from config: issuer (Sepolia, w5), sibling v4 pool
///         (Base Sepolia, w2), and the destination pool itself (SELF, w0). Builds crafted LogRecords.
abstract contract ReactiveFixture is ReactiveHarness {
    using stdJson for string;

    uint256 internal constant REACTIVE_IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;
    uint256 internal constant ORIGIN = 11_155_111; // Ethereum Sepolia
    uint256 internal constant DEST = 84_532; // Base Sepolia
    bytes32 internal constant SIBLING_POOL = bytes32(uint256(0x5151));

    string internal json;
    QuorumParams internal qp;
    RiskParams internal rp;
    GasLimits internal gl;
    NightShiftReactive internal rx;
    address internal issuer = makeAddr("issuer");
    address internal originPm = makeAddr("originPoolManager");
    address internal destPm = makeAddr("destPoolManager");
    address internal controllerAddr = makeAddr("controller");
    bytes32 internal destPool = bytes32(uint256(0xd00d));

    uint256 internal constant I_ISSUER = 0;
    uint256 internal constant I_SIBLING = 1;
    uint256 internal constant I_SELF = 2;

    /// @dev UTC timestamp helper.
    function _utc(uint256 y, uint256 m, uint256 d, uint256 hh, uint256 mm) internal pure returns (uint256) {
        return NyseCalendar.daysFromCivil(y, m, d) * 1 days + hh * 1 hours + mm * 1 minutes;
    }

    function _source(uint256 chainId, address emitter, uint256 topic0, uint256 topic1, SourceKind kind, uint16 weight)
        internal
        view
        returns (WitnessSource memory s)
    {
        s.chainId = chainId;
        s.emitter = emitter;
        s.topic0 = topic0;
        s.topic1 = topic1;
        s.kind = kind;
        s.weight = weight;
        s.maxAgeOpen = uint32(json.readUint(".witness.maxAgeOpenSeconds"));
        s.maxAgeClosed = uint32(json.readUint(".witness.maxAgeClosedSeconds"));
        s.enabled = true;
    }

    function _deployReactive(uint256 startTime) internal {
        vm.warp(startTime);
        _etchSystem();
        json = NightShiftConfig.load("testnet");
        qp = NightShiftConfig.quorumParams(json);
        rp = NightShiftConfig.riskParams(json);
        gl = NightShiftConfig.gasLimits(json);
        rx = new NightShiftReactive(DEST, destPool, qp, rp, gl, NightShiftConfig.cronTopic(json));
        rx.addSource(
            _source(
                ORIGIN,
                issuer,
                rx.MINTED_TOPIC0(),
                REACTIVE_IGNORE,
                SourceKind.ISSUER_MINT,
                uint16(json.readUint(".sourceWeights.issuerMintRedeem"))
            )
        );
        rx.addSource(
            _source(
                DEST,
                destPm,
                rx.V4_SWAP_TOPIC0(),
                uint256(SIBLING_POOL),
                SourceKind.V4_SWAP,
                uint16(json.readUint(".sourceWeights.v4SwapOther"))
            )
        );
        rx.addSource(_source(DEST, destPm, rx.V4_SWAP_TOPIC0(), uint256(destPool), SourceKind.SELF, 0));
        rx.subscribeCron();
        rx.setController(controllerAddr);
    }

    // ---------------------------------------------------------------- crafted logs

    function _issuerLog(uint256 shares, uint256 quoteAmount) internal view returns (IReactive.LogRecord memory l) {
        l.chainId = ORIGIN;
        l.contractAddress = issuer;
        l.topic0 = uint256(keccak256("Minted(address,uint256,uint256)"));
        l.data = abi.encode(shares, quoteAmount);
    }

    function _swapLog(bytes32 pool, int24 tick) internal view returns (IReactive.LogRecord memory l) {
        l.chainId = DEST;
        l.contractAddress = destPm;
        l.topic0 = uint256(keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)"));
        l.topic1 = uint256(pool);
        l.data = abi.encode(int128(-1e18), int128(1e18), uint160(1 << 96), uint128(1e18), tick, uint24(3000));
    }

    function _cronLog() internal view returns (IReactive.LogRecord memory l) {
        l.chainId = block.chainid;
        l.contractAddress = 0x0000000000000000000000000000000000fffFfF;
        l.topic0 = rx.cronTopic();
    }

    function _react(IReactive.LogRecord memory l) internal {
        vm.prank(SYSTEM_ADDR);
        rx.react(l);
    }

    /// @dev Issuer price as raw quote per 1e18 shares (tick = log1.0001(price/1e18)).
    function _issuerAt(uint256 priceWad) internal {
        _react(_issuerLog(1e18, priceWad));
    }

    function _selector(uint256 i) internal view returns (bytes4 sel) {
        bytes memory p = sys.queuedAt(i).config.payload;
        assembly {
            sel := mload(add(p, 32))
        }
    }
}
