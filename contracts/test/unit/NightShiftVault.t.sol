// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HookFixture} from "../utils/HookFixture.sol";
import {NightShiftVault} from "../../src/vault/NightShiftVault.sol";
import {Mandate, Regime} from "../../src/libraries/Types.sol";
import {NightShiftConfig} from "../../script/utils/NightShiftConfig.sol";

contract NightShiftVaultTest is HookFixture {
    NightShiftVault vault;
    Mandate m;
    address curator = makeAddr("curator");
    address alice = makeAddr("alice");
    uint64 seq;

    function setUp() public {
        _deployHookAndPool(_satNoon()); // CLOSED; this test contract acts as Controller for hook + vault
        vm.prank(hookOwner);
        hook.initController(address(this));
        m = NightShiftConfig.mandate(NightShiftConfig.load("testnet"), "balanced");
        vault = new NightShiftVault(manager, key, address(this), curator, m, "Balanced Night", "bNIGHT");
        _approve(address(this));
        _fund(alice);
    }

    function _approve(address who) internal {
        vm.startPrank(who);
        IERC20(Currency.unwrap(currency0)).approve(address(vault), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function _fund(address who) internal {
        IERC20(Currency.unwrap(currency0)).transfer(who, 1e24);
        IERC20(Currency.unwrap(currency1)).transfer(who, 1e24);
        _approve(who);
    }

    function _anchor(int24 a, uint16 risk) internal {
        hook.setState(poolId, a, risk, 0, ++seq);
    }

    function _bal(address who) internal view returns (uint256, uint256) {
        return (IERC20(Currency.unwrap(currency0)).balanceOf(who), IERC20(Currency.unwrap(currency1)).balanceOf(who));
    }

    function _tick() internal view returns (int24 t) {
        (, t,,) = StateLibrary.getSlot0(manager, poolId);
    }

    // ---------------------------------------------------------------- construction + auth

    function test_constructor_revert_perfFeeAboveCap() public {
        m.perfFeeBps = 2001;
        vm.expectRevert(NightShiftVault.PerfFeeTooHigh.selector);
        new NightShiftVault(manager, key, address(this), curator, m, "x", "x");
    }

    function test_onlyController() public {
        vm.startPrank(alice);
        vm.expectRevert(NightShiftVault.NotController.selector);
        vault.rebalance(0, 0, Regime.CLOSED);
        vm.expectRevert(NightShiftVault.NotController.selector);
        vault.snapshotClose(1);
        vm.expectRevert(NightShiftVault.NotController.selector);
        vault.reconcile(1, 0, false);
        vm.stopPrank();
    }

    function test_unlockCallback_onlyPoolManager() public {
        vm.expectRevert(NightShiftVault.NotPoolManager.selector);
        vault.unlockCallback(abi.encode(int24(0), int24(60), int256(1)));
    }

    // ---------------------------------------------------------------- in-kind pro-rata flows

    function test_firstDeposit_needsBothTokens() public {
        vm.expectRevert(NightShiftVault.ZeroAmount.selector);
        vault.deposit(1e18, 0, 0, address(this));
    }

    function test_deposit_withdraw_roundTrip_noPosition() public {
        (uint256 shares,,) = vault.deposit(4e18, 1e18, 0, address(this));
        assertEq(shares, 2e18); // sqrt(4e18 * 1e18)
        (uint256 a0, uint256 a1) = vault.withdraw(shares, 0, 0, address(this));
        assertEq(a0, 4e18);
        assertEq(a1, 1e18);
        assertEq(vault.totalSupply(), 0);
    }

    function test_secondDeposit_proRata_atCurrentComposition() public {
        vault.deposit(10e18, 10e18, 0, address(this));
        _anchor(0, 0);
        vault.rebalance(0, 0, Regime.CLOSED);
        (uint256 t0, uint256 t1) = vault.totals();
        uint256 supply = vault.totalSupply();
        vm.prank(alice);
        (uint256 s, uint256 a0, uint256 a1) = vault.deposit(5e18, 100e18, 0, alice); // token0-limited
        assertApproxEqRel(s, supply * 5e18 / t0, 1e12);
        assertApproxEqRel(a1 * t0, a0 * t1, 1e12, "same composition as the vault");
        assertLe(a1, 100e18, "excess not taken");
    }

    function test_withdraw_proRata_fromPosition() public {
        vault.deposit(10e18, 10e18, 0, address(this));
        _anchor(0, 0);
        vault.rebalance(0, 0, Regime.CLOSED);
        vm.prank(alice);
        (uint256 s,,) = vault.deposit(10e18, 10e18, 0, alice);
        (uint256 b0, uint256 b1) = _bal(alice);
        vm.prank(alice);
        (uint256 o0, uint256 o1) = vault.withdraw(s, 0, 0, alice);
        (uint256 c0, uint256 c1) = _bal(alice);
        assertEq(c0 - b0, o0);
        assertEq(c1 - b1, o1);
        assertApproxEqRel(o0, 10e18, 1e15, "gets back ~what it put in (no trades in between)");
        assertApproxEqRel(o1, 10e18, 1e15);
    }

    function test_withdraw_slippageGuard() public {
        (uint256 s,,) = vault.deposit(1e18, 1e18, 0, address(this));
        vm.expectRevert(NightShiftVault.InsufficientOutput.selector);
        vault.withdraw(s, 2e18, 0, address(this));
    }

    // ---------------------------------------------------------------- rebalance geometry (README §10.2)

    function test_rebalance_followsAnchor_withNoTrade() public {
        vault.deposit(10e18, 10e18, 0, address(this));
        _anchor(600, 0);
        vault.rebalance(600, 0, Regime.CLOSED); // closed follow = 100% → center on the anchor
        int24 c = (vault.lower() + vault.upper()) / 2;
        assertApproxEqAbs(int256(c), 600, 60, "centered on the witnessed fair price");
        assertApproxEqAbs(int256(vault.upper() - vault.lower()), 2 * int256(uint256(m.closed.coreHalfWidth)), 120);
        assertGt(vault.liquidity(), 0);
        assertEq(_tick(), 0, "pool untouched");
    }

    function test_rebalance_skipsSmallMove() public {
        vault.deposit(10e18, 10e18, 0, address(this));
        vault.rebalance(0, 0, Regime.CLOSED);
        (int24 lo, int24 hi) = (vault.lower(), vault.upper());
        vm.expectEmit(false, false, false, false, address(vault));
        emit NightShiftVault.RebalanceSkipped(0, 0);
        vault.rebalance(int24(uint24(m.closed.recenterThreshold)) - 1, 0, Regime.CLOSED);
        assertEq(vault.lower(), lo);
        assertEq(vault.upper(), hi);
    }

    function test_rebalance_riskWidensRange() public {
        vault.deposit(10e18, 10e18, 0, address(this));
        vault.rebalance(0, 0, Regime.CLOSED);
        int24 narrow = vault.upper() - vault.lower();
        vault.rebalance(0, 5000, Regime.CLOSED);
        assertGt(vault.upper() - vault.lower(), narrow, "higher risk -> wider range");
    }

    function test_rebalance_exitsAtHighRisk() public {
        vault.deposit(10e18, 10e18, 0, address(this));
        vault.rebalance(0, 0, Regime.CLOSED);
        vault.rebalance(0, m.closed.exitRiskBps, Regime.CLOSED);
        assertEq(vault.liquidity(), 0, "core pulled at exit risk");
        (uint256 t0, uint256 t1) = vault.totals();
        assertApproxEqRel(t0, 10e18, 1e15, "funds safe in the vault");
        assertApproxEqRel(t1, 10e18, 1e15);
    }

    function test_openMandate_followsPartially() public {
        vault.deposit(10e18, 10e18, 0, address(this));
        vault.rebalance(1000, 0, Regime.OPEN); // open follow = 70%
        int24 c = (vault.lower() + vault.upper()) / 2;
        assertApproxEqAbs(int256(c), int256(uint256(m.open.followBps)) * 1000 / 10_000, 60);
    }

    // ---------------------------------------------------------------- reconcile vs HODL + HWM (README §11)

    function test_reconcile_feesBeatHodl_curatorPaidAboveHwm() public {
        hook.setRegime(poolId, Regime.OPEN, ++seq); // no move caps for the round trips
        _anchor(0, 0);
        vault.deposit(100e18, 100e18, 0, address(this));
        vault.rebalance(0, 0, Regime.OPEN);
        vault.snapshotClose(1);
        // traders round-trip through the vault's range: price returns to tick 0, LPs keep the fees
        for (uint256 i; i < 5; i++) {
            _swapTo(false, 300);
            _swapTo(true, 0);
        }
        (uint160 sqrtP,,,) = StateLibrary.getSlot0(manager, poolId);
        assertEq(sqrtP, SQRT_PRICE_1_1, "back at the starting price");
        vault.reconcile(1, 0, false);
        assertGt(vault.lastAlpha(), 0, "fees -> positive alpha vs HODL");
        assertEq(vault.cumAlpha(), vault.hwm());
        assertGt(vault.balanceOf(curator), 0, "perf fee minted above HWM");
        assertEq(vault.epochsPlayed(), 1);
    }

    function test_reconcile_negativeEpoch_noFee_hwmKept() public {
        _anchor(0, 0);
        vault.deposit(100e18, 100e18, 0, address(this));
        vault.rebalance(0, 0, Regime.CLOSED);
        vault.snapshotClose(1);
        // reopen far away: a concentrated LP underperforms HODL (impermanent loss)
        vault.reconcile(1, 3000, false);
        assertLt(vault.lastAlpha(), 0);
        assertEq(vault.hwm(), 0, "HWM unchanged");
        assertEq(vault.balanceOf(curator), 0, "no perf fee below HWM");
    }

    function test_reconcile_withoutSnapshot_noop() public {
        vault.deposit(1e18, 1e18, 0, address(this));
        vault.reconcile(1, 0, false);
        assertEq(vault.epochsPlayed(), 0);
    }
}
