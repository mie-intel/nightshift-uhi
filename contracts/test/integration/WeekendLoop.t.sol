// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IReactive} from "@reactive/interfaces/IReactive.sol";

import {HookFixture} from "../utils/HookFixture.sol";
import {ReactiveFixture} from "../utils/ReactiveFixture.sol";
import {NightShiftController} from "../../src/controller/NightShiftController.sol";
import {DemoToken} from "../../src/mocks/DemoToken.sol";
import {MockIssuer} from "../../src/mocks/MockIssuer.sol";
import {FeeMath} from "../../src/libraries/FeeMath.sol";
import {PriceMath} from "../../src/libraries/PriceMath.sol";
import {Regime} from "../../src/libraries/Types.sol";
import {NightShiftVault} from "../../src/vault/NightShiftVault.sol";
import {VaultFactory} from "../../src/vault/VaultFactory.sol";
import {NightShiftConfig} from "../../script/utils/NightShiftConfig.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title A full NightShift weekend, locally, with every real contract (SPEC §21.2 integration test).
/// @notice Fri close → Saturday news on two other chains → the pool is repriced with no trade on it → repair served,
///         away capped → Monday open window → reconciliation → OPEN. Reactive is simulated by the ReactiveHarness.
contract WeekendLoopTest is HookFixture, ReactiveFixture {
    address callbackProxy = makeAddr("callbackProxy");
    address trader = makeAddr("trader");
    MockIssuer mi;
    NightShiftController ctrl;
    VaultFactory factory;
    NightShiftVault vault;
    address curator = makeAddr("curator");
    bytes32 constant SWAP_TOPIC = keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)");

    function setUp() public {
        uint256 friOpen = _utc(2026, 11, 20, 20, 0);
        _deployHookAndPool(friOpen); // pool at tick 0, hook regime OPEN

        DemoToken stock = new DemoToken("Demo Stock", "dSTOCK", 18);
        DemoToken usd = new DemoToken("Demo USD", "dUSD", 18);
        mi = new MockIssuer(stock, usd, 1e18);
        stock.setMinter(address(mi), true);
        usd.mint(trader, 1_000_000e18);
        vm.prank(trader);
        usd.approve(address(mi), type(uint256).max);

        issuer = address(mi);
        destPm = address(manager);
        destPool = PoolId.unwrap(poolId);
        _deployReactive(friOpen);

        ctrl = new NightShiftController(callbackProxy, address(rx), hook, qp.reconcileTimeoutSeconds);
        vm.prank(hookOwner);
        hook.initController(address(ctrl));
        rx.setController(address(ctrl));

        // a curator opens a Balanced vault; depositors follow it
        factory = new VaultFactory(manager, key, address(ctrl));
        ctrl.setFactory(address(factory));
        vm.prank(curator);
        vault = NightShiftVault(factory.create(NightShiftConfig.mandate(json, "balanced"), "Balanced Night", "bNIGHT"));
        IERC20(Currency.unwrap(currency0)).approve(address(vault), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(vault), type(uint256).max);
        vault.deposit(1000e18, 1000e18, 0, address(this));
    }

    // ---------------------------------------------------------------- the three chains

    /// @dev Ethereum Sepolia: issuer trades at `price` (dUSD per dSTOCK, wad).
    function _issuerTrades(uint256 price) internal {
        mi.setPrice(price);
        vm.recordLogs();
        vm.prank(trader);
        mi.mint(1e18);
        _react(_capture(vm.getRecordedLogs(), address(mi), MockIssuer.Minted.selector, ORIGIN));
    }

    /// @dev Base Sepolia: a sibling v4 pool prints at `tick`.
    function _siblingTrades(int24 tick) internal {
        _react(_swapLog(SIBLING_POOL, tick));
    }

    /// @dev Base Sepolia: someone trades OUR pool; Reactive sees our own Swap (SELF → divergence).
    function _poolTrade(bool zeroForOne, int24 target) internal {
        vm.recordLogs();
        _swapTo(zeroForOne, target);
        _react(_capture(vm.getRecordedLogs(), address(manager), SWAP_TOPIC, DEST));
    }

    function _cron(uint256 t) internal {
        vm.warp(t);
        _react(_cronLog());
    }

    function _deliver() internal returns (uint256) {
        return _relayCallbacks(callbackProxy);
    }

    function _hookAnchor() internal view returns (int24 a) {
        (a,,,,,,,,) = hook.poolState(poolId);
    }

    function _absDiff(int24 a, int24 b) internal pure returns (uint256) {
        return a >= b ? uint256(int256(a) - b) : uint256(int256(b) - a);
    }

    function _poolTick() internal view returns (int24 t) {
        (, t,,) = StateLibrary.getSlot0(manager, poolId);
    }

    // ---------------------------------------------------------------- the story

    function test_weekend_closeNewsRepairReopen() public {
        // Friday 20:30 — market open, witnesses agree at 1.00
        vm.warp(_utc(2026, 11, 20, 20, 30));
        _issuerTrades(1e18);
        _siblingTrades(0);
        assertEq(_deliver(), 1, "first anchor");
        assertEq(_hookAnchor(), 0);
        assertGt(vault.liquidity(), 0, "vault deployed on the fair price by the first callback");

        // Friday 21:00 — NYSE closes; Cron flips the regime on Reactive → pool CLOSED
        _cron(_utc(2026, 11, 20, 21, 0));
        _deliver();
        assertEq(uint8(hook.regimeOf(poolId)), uint8(Regime.CLOSED), "pool closed by Reactive");
        assertTrue(vault.snapshotOpen(), "vault snapshot at the close");
        console.log("Fri 21:00 UTC  NYSE closed -> pool CLOSED via onRegime");

        // Saturday 12:00 — news: the issuer and a sibling pool both reprice +4% on other chains
        //   one print can move the anchor by at most maxJumpTicks (300): no teleporting on a single trade
        vm.warp(_utc(2026, 11, 21, 12, 0));
        _issuerTrades(1.04e18);
        vm.warp(block.timestamp + 1 minutes);
        _siblingTrades(PriceMath.tickFromRatio(1.04e18, 1e18));
        _deliver();
        assertEq(_hookAnchor(), int24(qp.maxJumpTicks), "first print capped at maxJumpTicks");
        //   the news keeps trading for half an hour → EWMA converges
        for (uint256 i; i < 6; i++) {
            vm.warp(block.timestamp + 5 minutes);
            _issuerTrades(1.04e18);
            _siblingTrades(PriceMath.tickFromRatio(1.04e18, 1e18));
            _deliver();
        }
        assertApproxEqAbs(int256(rx.anchor()), 392, 4, "Reactive anchor converges within minutes (+4% ~ 392 ticks)");
        int24 fair = _hookAnchor();
        assertLt(
            _absDiff(fair, rx.anchor()), qp.minAnchorDeltaTicks, "hook within debounce threshold (no callback spam)"
        );
        assertEq(_poolTick(), 0, "no trade on our pool yet - repriced between trades");
        int24 vaultCenter = (vault.lower() + vault.upper()) / 2;
        assertApproxEqAbs(int256(vaultCenter), int256(fair), 70, "vault recentered on fair value with no trade");
        console.log("vault liquidity recentered around tick", int256(vaultCenter));
        console.log("Sat 12:00 UTC  issuer +4% on Sepolia + sibling on Base -> pool anchor tick", int256(fair));

        // repair flow is served all the way to fair value…
        (uint24 repairFee, bool away) = hook.quoteFee(key, false);
        assertFalse(away);
        _poolTrade(false, fair);
        assertEq(_poolTick(), fair);
        console.log("repair swap served to fair value, fee (pips)", repairFee);

        // …and pushing past fair value is capped
        vm.expectRevert(_wrapped(IHooks.afterSwap.selector, FeeMath.Overshoot.selector));
        _swapTo(false, fair + int24(cfg.overshootCap) + 1);

        // Monday 14:30 — NYSE opens → REOPEN_PENDING; witnesses in the open window; 14:45 → reconcile → OPEN
        _cron(_utc(2026, 11, 23, 14, 30));
        _deliver();
        assertEq(uint8(hook.regimeOf(poolId)), uint8(Regime.REOPEN_PENDING));
        vm.warp(_utc(2026, 11, 23, 14, 35));
        _issuerTrades(1.041e18);
        _siblingTrades(PriceMath.tickFromRatio(1.041e18, 1e18));
        _deliver();
        vm.recordLogs();
        _cron(_utc(2026, 11, 23, 14, 45));
        _deliver();
        assertEq(uint8(hook.regimeOf(poolId)), uint8(Regime.OPEN), "reconciled at the open");
        assertEq(rx.epochId(), 1);
        assertEq(vault.epochsPlayed(), 1, "vault scored vs HODL at the open");
        console.log("vault alpha vs HODL (currency1 wad/share)", vault.lastAlpha());
        console.log("Mon 14:45 UTC  open window closed -> onReconcile -> pool OPEN");
    }

    /// @dev The onAnchor callback (hook + vault fan-out) must fit its configured gas limit.
    function test_onAnchorCallback_gas_withVault() public {
        vm.warp(_utc(2026, 11, 20, 20, 30));
        _issuerTrades(1e18);
        _siblingTrades(0);
        bytes memory payload = sys.queuedAt(0).config.payload;
        address r = address(rx);
        assembly ("memory-safe") {
            mstore(add(payload, 36), r)
        }
        vm.prank(callbackProxy);
        uint256 g = gasleft();
        (bool ok,) = address(ctrl).call(payload);
        uint256 used = g - gasleft();
        assertTrue(ok);
        emit log_named_uint("onAnchor gas (1 vault)", used);
        assertLt(used * 8, gl.onAnchor * 3, "room for ~8 vaults within the callback gas limit"); // ~used < 940k
    }

    /// @dev S5: witnesses go silent while closed → anchor goes stale on the hook → every trade is max-protected.
    function test_witnessOutage_hookFallsBackToMaxProtection() public {
        vm.warp(_utc(2026, 11, 20, 20, 30));
        _issuerTrades(1e18);
        _siblingTrades(0);
        _cron(_utc(2026, 11, 20, 21, 0));
        _deliver();
        vm.warp(block.timestamp + cfg.anchorMaxAgeClosed + 1);
        _cron(block.timestamp);
        _deliver();
        (, bool awayBuy) = hook.quoteFee(key, false);
        (, bool awaySell) = hook.quoteFee(key, true);
        assertTrue(awayBuy && awaySell, "stale anchor: both directions treated as away");
        assertFalse(rx.quorum());
    }

    /// @dev Calendar fallback: if Reactive is late, anyone can close the pool on the destination chain.
    function test_syncRegime_fallback_whenReactiveLate() public {
        vm.warp(_utc(2026, 11, 20, 21, 5)); // closed, but no Cron delivered
        assertEq(uint8(hook.regimeOf(poolId)), uint8(Regime.OPEN));
        vm.prank(makeAddr("anyone"));
        ctrl.syncRegime(destPool);
        assertEq(uint8(hook.regimeOf(poolId)), uint8(Regime.CLOSED));
        // the late Reactive callback still lands (regime seq channel) and agrees
        _cron(block.timestamp);
        _deliver();
        assertEq(uint8(hook.regimeOf(poolId)), uint8(Regime.CLOSED));
    }

    function test_forgedCallback_rejected() public {
        vm.expectRevert();
        ctrl.onAnchor(address(rx), destPool, 99, 0, 0, 0, 2, 0); // not from the proxy
        vm.prank(callbackProxy);
        vm.expectRevert();
        ctrl.onRegime(makeAddr("impostor"), destPool, 99, uint8(Regime.OPEN), 0); // wrong reactive identity
    }
}
