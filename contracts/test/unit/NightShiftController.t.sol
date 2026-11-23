// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {AbstractPayer} from "@reactive/base/AbstractPayer.sol";
import {AbstractCallback} from "@reactive/base/AbstractCallback.sol";

import {NightShiftController} from "../../src/controller/NightShiftController.sol";
import {INightShiftHook} from "../../src/interfaces/INightShiftHook.sol";
import {NyseCalendar} from "../../src/libraries/NyseCalendar.sol";
import {Regime} from "../../src/libraries/Types.sol";

contract RecordingHook is INightShiftHook {
    bytes32 public lastId;
    int24 public lastAnchor;
    uint16 public lastRisk;
    uint64 public lastSeq;
    uint64 public lastRegimeSeq;
    uint256 public calls;
    mapping(bytes32 => Regime) public regimes;
    uint256 public forced;

    function setState(PoolId id, int24 a, uint16 r, uint16, uint64 s) external {
        (lastId, lastAnchor, lastRisk, lastSeq) = (PoolId.unwrap(id), a, r, s);
        calls++;
    }

    function setRegime(PoolId id, Regime r, uint64 s) external {
        regimes[PoolId.unwrap(id)] = r;
        lastRegimeSeq = s;
    }

    function forceRegime(PoolId id, Regime r) external {
        regimes[PoolId.unwrap(id)] = r;
        forced++;
    }

    function anchorOf(PoolId) external pure returns (int24) {
        return 77;
    }

    function regimeOf(PoolId id) external view returns (Regime) {
        return regimes[PoolId.unwrap(id)];
    }

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

/// @dev Counts close snapshots; other vault calls are not exercised by these tests.
contract CountingVault {
    uint256 public snapshots;

    function snapshotClose(uint64) external {
        snapshots++;
    }

    function reconcile(uint64, int24, bool) external {}
}

contract NightShiftControllerTest is Test {
    DebtProxy proxy;
    address reactive = makeAddr("reactive");
    RecordingHook hook;
    NightShiftController ctrl;
    bytes32 constant POOL = bytes32(uint256(0xabc));
    uint256 constant TIMEOUT = 3600;

    function setUp() public {
        proxy = new DebtProxy();
        hook = new RecordingHook();
        ctrl = new NightShiftController(address(proxy), reactive, hook, TIMEOUT);
    }

    function _utc(uint256 y, uint256 m, uint256 d, uint256 hh) internal pure returns (uint256) {
        return NyseCalendar.daysFromCivil(y, m, d) * 1 days + hh * 1 hours;
    }

    function _onAnchor(address identity) internal {
        ctrl.onAnchor(identity, POOL, 7, -230_271, 1234, 5, 1, uint40(block.timestamp));
    }

    // ---------------------------------------------------------------- callback auth (invariant 1, ADR-008)

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
    function test_callbacks_revert_wrongSender() public {
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), address(proxy)));
        _onAnchor(reactive);
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), address(proxy)));
        ctrl.onRegime(reactive, POOL, 1, uint8(Regime.CLOSED), 0);
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), address(proxy)));
        ctrl.onReconcile(reactive, POOL, 1, 1, 0, 0, false);
    }

    /// @dev Proxy delivering a callback from a different reactive contract is rejected (onlyCallbackSender).
    function test_callbacks_revert_wrongIdentity() public {
        address impostor = makeAddr("impostor");
        vm.startPrank(address(proxy));
        vm.expectRevert(abi.encodeWithSelector(AbstractCallback.CallbackNotAuthorized.selector, impostor, reactive));
        _onAnchor(impostor);
        vm.expectRevert(abi.encodeWithSelector(AbstractCallback.CallbackNotAuthorized.selector, impostor, reactive));
        ctrl.onRegime(impostor, POOL, 1, uint8(Regime.CLOSED), 0);
        vm.expectRevert(abi.encodeWithSelector(AbstractCallback.CallbackNotAuthorized.selector, impostor, reactive));
        ctrl.onReconcile(impostor, POOL, 1, 1, 0, 0, false);
        vm.stopPrank();
        assertEq(hook.calls(), 0);
    }

    // ---------------------------------------------------------------- regime + reconcile callbacks

    function test_onRegime_setsHookRegime_tracksReopen() public {
        vm.startPrank(address(proxy));
        ctrl.onRegime(reactive, POOL, 3, uint8(Regime.CLOSED), uint40(block.timestamp));
        assertEq(uint8(hook.regimeOf(PoolId.wrap(POOL))), uint8(Regime.CLOSED));
        assertEq(hook.lastRegimeSeq(), 3);
        ctrl.onRegime(reactive, POOL, 4, uint8(Regime.REOPEN_PENDING), uint40(block.timestamp));
        vm.stopPrank();
        assertEq(ctrl.reopenPendingAt(POOL), block.timestamp);
    }

    function test_onReconcile_opensPool() public {
        vm.startPrank(address(proxy));
        ctrl.onRegime(reactive, POOL, 1, uint8(Regime.REOPEN_PENDING), 0);
        vm.expectEmit(true, false, false, true, address(ctrl));
        emit NightShiftController.Reconciled(POOL, 2, 123, 99, false);
        ctrl.onReconcile(reactive, POOL, 2, 2, 123, 99, false);
        vm.stopPrank();
        assertEq(uint8(hook.regimeOf(PoolId.wrap(POOL))), uint8(Regime.OPEN));
        assertEq(ctrl.reopenPendingAt(POOL), 0);
    }

    // ---------------------------------------------------------------- permissionless fallbacks (SPEC §6.3)

    function test_syncRegime_closesWhenCalendarClosed() public {
        vm.warp(_utc(2026, 11, 21, 12)); // Saturday
        ctrl.syncRegime(POOL); // hook regime OPEN (default) → CLOSED
        assertEq(uint8(hook.regimeOf(PoolId.wrap(POOL))), uint8(Regime.CLOSED));
        vm.expectRevert(NightShiftController.NothingToSync.selector);
        ctrl.syncRegime(POOL);
    }

    function test_syncRegime_reopensWhenCalendarOpen() public {
        vm.warp(_utc(2026, 11, 21, 12));
        ctrl.syncRegime(POOL);
        vm.warp(_utc(2026, 11, 23, 15)); // Monday session
        ctrl.syncRegime(POOL);
        assertEq(uint8(hook.regimeOf(PoolId.wrap(POOL))), uint8(Regime.REOPEN_PENDING));
        assertEq(ctrl.reopenPendingAt(POOL), block.timestamp);
    }

    function test_forceReconcile_onlyAfterTimeout() public {
        vm.warp(_utc(2026, 11, 21, 12));
        ctrl.syncRegime(POOL);
        vm.warp(_utc(2026, 11, 23, 15));
        ctrl.syncRegime(POOL);
        vm.expectRevert(NightShiftController.ReconcileNotDue.selector);
        ctrl.forceReconcile(POOL);
        vm.warp(block.timestamp + TIMEOUT);
        ctrl.forceReconcile(POOL);
        assertEq(uint8(hook.regimeOf(PoolId.wrap(POOL))), uint8(Regime.OPEN));
        vm.expectRevert(NightShiftController.ReconcileNotDue.selector);
        ctrl.forceReconcile(POOL);
    }

    /// @dev Regression: a Reactive close callback landing after `syncRegime` started a second epoch and re-snapshotted.
    function test_lateCloseCallback_afterSync_keepsOneEpoch() public {
        CountingVault v = new CountingVault();
        ctrl.addVault(POOL, address(v));
        vm.warp(_utc(2026, 11, 21, 12));
        ctrl.syncRegime(POOL);
        vm.warp(block.timestamp + 10 minutes);
        vm.prank(address(proxy));
        ctrl.onRegime(reactive, POOL, 1, uint8(Regime.CLOSED), uint40(block.timestamp));
        assertEq(ctrl.epochOf(POOL), 1);
        assertEq(v.snapshots(), 1);
    }

    function test_eachCloseStartsOneEpoch() public {
        CountingVault v = new CountingVault();
        ctrl.addVault(POOL, address(v));
        vm.startPrank(address(proxy));
        ctrl.onRegime(reactive, POOL, 1, uint8(Regime.CLOSED), 0);
        ctrl.onRegime(reactive, POOL, 2, uint8(Regime.REOPEN_PENDING), 0);
        ctrl.onReconcile(reactive, POOL, 3, 1, 0, 0, false);
        ctrl.onRegime(reactive, POOL, 4, uint8(Regime.CLOSED), 0);
        vm.stopPrank();
        assertEq(ctrl.epochOf(POOL), 2);
        assertEq(v.snapshots(), 2);
    }

    // ---------------------------------------------------------------- funding

    function test_coverDebt_paysProxy() public {
        vm.deal(address(ctrl), 1 ether);
        proxy.setDebt(0.1 ether);
        ctrl.coverDebt();
        assertEq(address(proxy).balance, 0.1 ether);
        assertEq(proxy.owed(), 0);
    }

    function test_registry_and_withdraw_adminOnly() public {
        vm.startPrank(makeAddr("rando"));
        vm.expectRevert(NightShiftController.NotRegistrar.selector);
        ctrl.setFactory(address(1));
        vm.expectRevert(NightShiftController.NotRegistrar.selector);
        ctrl.addVault(POOL, address(1));
        vm.expectRevert(NightShiftController.NotRegistrar.selector);
        ctrl.withdraw(payable(address(1)), 0);
        vm.stopPrank();
        ctrl.setFactory(address(this));
        vm.expectRevert(NightShiftController.NotRegistrar.selector);
        ctrl.setFactory(address(2)); // once
        for (uint256 i; i < ctrl.MAX_VAULTS_PER_POOL(); i++) {
            ctrl.addVault(POOL, address(uint160(100 + i)));
        }
        vm.expectRevert(NightShiftController.TooManyVaults.selector);
        ctrl.addVault(POOL, address(1));
        assertEq(ctrl.vaultsOf(POOL).length, 8);
        vm.deal(address(ctrl), 1 ether);
        address payable to = payable(makeAddr("to"));
        ctrl.withdraw(to, 0.3 ether);
        assertEq(to.balance, 0.3 ether);
    }

    function test_receivesFunding() public {
        (bool ok,) = address(ctrl).call{value: 1 ether}("");
        assertTrue(ok);
    }
}
