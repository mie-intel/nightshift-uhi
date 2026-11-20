// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IReactive} from "@reactive/interfaces/IReactive.sol";
import {AbstractPayer} from "@reactive/base/AbstractPayer.sol";

import {NightShiftReactive} from "../../src/reactive/NightShiftReactive.sol";
import {MockSystemContract} from "../../src/mocks/MockSystemContract.sol";
import {INightShiftController} from "../../src/interfaces/INightShiftController.sol";
import {PriceMath} from "../../src/libraries/PriceMath.sol";

contract NightShiftReactiveTest is Test {
    address constant SYSTEM = 0x8888888888888888888888888888888888888888;
    uint256 constant REACTIVE_IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;
    uint256 constant DEST = 1301;
    uint256 constant ORIGIN = 11_155_111;
    bytes32 constant POOL = bytes32(uint256(0xabc));

    MockSystemContract sys;
    NightShiftReactive rx;
    address issuer = makeAddr("issuer");
    address controller = makeAddr("controller");

    function setUp() public {
        vm.etch(SYSTEM, type(MockSystemContract).runtimeCode);
        sys = MockSystemContract(payable(SYSTEM));
        rx = new NightShiftReactive(DEST, POOL, ORIGIN, issuer, false, 0, 2_500_000);
    }

    function _mintLog(uint256 shares, uint256 quoteAmount) internal returns (IReactive.LogRecord memory l) {
        l.chainId = ORIGIN;
        l.contractAddress = issuer;
        l.topic0 = rx.MINTED_TOPIC0();
        l.topic1 = uint256(uint160(makeAddr("minter")));
        l.data = abi.encode(shares, quoteAmount);
        l.blockNumber = 123;
    }

    function test_mintedTopic_matchesMockIssuerEvent() public view {
        assertEq(rx.MINTED_TOPIC0(), uint256(keccak256("Minted(address,uint256,uint256)")));
    }

    function test_subscribe_onlyOwner_recordsCriteria() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert(NightShiftReactive.NotOwner.selector);
        rx.subscribe();

        rx.subscribe();
        assertEq(sys.subCount(), 1);
        MockSystemContract.Sub memory s = sys.subAt(0);
        assertEq(s.subscriber, address(rx));
        assertEq(s.chainId, ORIGIN);
        assertEq(s.emitter, issuer);
        assertEq(s.topic0, rx.MINTED_TOPIC0());
        assertEq(s.topic1, REACTIVE_IGNORE);
        assertEq(s.topic2, REACTIVE_IGNORE);
        assertEq(s.topic3, REACTIVE_IGNORE);
    }

    function test_react_onlySystem() public {
        rx.setController(controller);
        IReactive.LogRecord memory l = _mintLog(1e18, 100e6);
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), SYSTEM));
        rx.react(l);
    }

    function test_react_revert_controllerNotSet() public {
        IReactive.LogRecord memory l = _mintLog(1e18, 100e6);
        vm.prank(SYSTEM);
        vm.expectRevert(NightShiftReactive.ControllerNotSet.selector);
        rx.react(l);
    }

    function test_react_revert_unexpectedLog() public {
        rx.setController(controller);
        IReactive.LogRecord memory l = _mintLog(1e18, 100e6);
        l.contractAddress = makeAddr("other");
        vm.prank(SYSTEM);
        vm.expectRevert(NightShiftReactive.UnexpectedLog.selector);
        rx.react(l);
    }

    /// @dev Issuer mints 2 dSTOCK for 200 dUSD → tick of 100e6/1e18 → onAnchor callback queued with exact payload.
    function test_react_issuerMint_requestsOnAnchorCallback() public {
        rx.setController(controller);
        IReactive.LogRecord memory l = _mintLog(2e18, 200e6);
        int24 expectedTick = PriceMath.tickFromRatio(200e6, 2e18);

        vm.prank(SYSTEM);
        rx.react(l);

        assertEq(sys.queueLength(), 1);
        MockSystemContract.Queued memory q = sys.queuedAt(0);
        assertEq(q.requester, address(rx));
        assertEq(q.config.chainId, DEST);
        assertEq(q.config.recipient, controller);
        assertEq(q.config.gasLimit, 2_500_000);
        bytes memory expected = abi.encodeWithSelector(
            INightShiftController.onAnchor.selector,
            address(0),
            POOL,
            uint64(1),
            expectedTick,
            uint16(0),
            uint16(0),
            uint8(1),
            uint40(block.timestamp)
        );
        assertEq(q.config.payload, expected);
        assertEq(rx.seq(), 1);
        assertEq(rx.lastAnchor(), expectedTick);
    }

    function test_react_seqIncrements() public {
        rx.setController(controller);
        vm.startPrank(SYSTEM);
        rx.react(_mintLog(1e18, 100e6));
        rx.react(_mintLog(1e18, 104e6));
        vm.stopPrank();
        assertEq(rx.seq(), 2);
        assertGt(rx.lastAnchor(), PriceMath.tickFromRatio(100e6, 1e18));
    }

    function test_react_invertAndOffset() public {
        NightShiftReactive inv = new NightShiftReactive(DEST, POOL, ORIGIN, issuer, true, 7, 2_500_000);
        inv.setController(controller);
        IReactive.LogRecord memory l = _mintLog(1e18, 100e6);
        vm.prank(SYSTEM);
        inv.react(l);
        assertEq(inv.lastAnchor(), -PriceMath.tickFromRatio(100e6, 1e18) + 7);
    }

    /// @dev react() must fit the 900k Reactive-tx cap.
    function test_react_gas_underReactiveCap() public {
        rx.setController(controller);
        IReactive.LogRecord memory l = _mintLog(1e18, 100e6);
        vm.prank(SYSTEM);
        uint256 g = gasleft();
        rx.react(l);
        assertLt(g - gasleft(), 900_000);
    }

    function test_coverDebt() public {
        vm.deal(address(rx), 1 ether);
        sys.setDebt(address(rx), 0.2 ether);
        rx.coverDebt();
        assertEq(sys.debt(address(rx)), 0);
        assertEq(SYSTEM.balance, 0.2 ether);
    }
}
