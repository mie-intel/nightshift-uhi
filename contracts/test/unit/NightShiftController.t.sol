// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {AbstractPayer} from "@reactive/base/AbstractPayer.sol";
import {AbstractCallback} from "@reactive/base/AbstractCallback.sol";

import {NightShiftController} from "../../src/controller/NightShiftController.sol";
import {INightShiftHook} from "../../src/interfaces/INightShiftHook.sol";
import {Regime} from "../../src/libraries/Types.sol";

contract RecordingHook is INightShiftHook {
    bytes32 public lastId;
    int24 public lastAnchor;
    uint16 public lastRisk;
    uint64 public lastSeq;
    uint256 public calls;

    function setState(PoolId id, int24 a, uint16 r, uint16, uint64 s) external {
        (lastId, lastAnchor, lastRisk, lastSeq) = (PoolId.unwrap(id), a, r, s);
        calls++;
    }

    function setRegime(PoolId, Regime, uint64) external {}

    function quoteFee(PoolKey calldata, bool) external pure returns (uint24, bool) {}
}

/// @dev Proxy stand-in whose debt() is settable; accepts payments.
contract DebtProxy {
    uint256 public owed;

    function setDebt(uint256 d) external {
        owed = d;
    }

    function debt(address) external view returns (uint256) {
        return owed;
    }

    receive() external payable {
        owed = 0;
    }
}

contract NightShiftControllerTest is Test {
    DebtProxy proxy;
    address reactive = makeAddr("reactive");
    RecordingHook hook;
    NightShiftController ctrl;
    bytes32 constant POOL = bytes32(uint256(0xabc));

    function setUp() public {
        proxy = new DebtProxy();
        hook = new RecordingHook();
        ctrl = new NightShiftController(address(proxy), reactive, hook);
    }

    function _onAnchor(address identity) internal {
        ctrl.onAnchor(identity, POOL, 7, -230_271, 1234, 5, 1, uint40(block.timestamp));
    }

    function test_onAnchor_happyPath_relaysToHook() public {
        vm.expectEmit(true, false, false, true, address(ctrl));
        emit NightShiftController.AnchorRelayed(POOL, 7, -230_271, 1234, 5, 1, uint40(block.timestamp));
        vm.prank(address(proxy));
        _onAnchor(reactive);
        assertEq(hook.calls(), 1);
        assertEq(hook.lastId(), POOL);
        assertEq(hook.lastAnchor(), -230_271);
        assertEq(hook.lastRisk(), 1234);
        assertEq(hook.lastSeq(), 7);
    }

    /// @dev Anyone calling directly with the right identity is rejected (onlyServiceProvider).
    function test_onAnchor_revert_wrongSender() public {
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), address(proxy)));
        _onAnchor(reactive);
    }

    /// @dev Proxy delivering a callback from a different reactive contract is rejected (onlyCallbackSender).
    function test_onAnchor_revert_wrongIdentity() public {
        address impostor = makeAddr("impostor");
        vm.prank(address(proxy));
        vm.expectRevert(abi.encodeWithSelector(AbstractCallback.CallbackNotAuthorized.selector, impostor, reactive));
        _onAnchor(impostor);
        assertEq(hook.calls(), 0);
    }

    function test_coverDebt_paysProxy() public {
        vm.deal(address(ctrl), 1 ether);
        proxy.setDebt(0.1 ether);
        ctrl.coverDebt();
        assertEq(address(proxy).balance, 0.1 ether);
        assertEq(proxy.owed(), 0);
    }

    function test_receivesFunding() public {
        (bool ok,) = address(ctrl).call{value: 1 ether}("");
        assertTrue(ok);
    }
}
