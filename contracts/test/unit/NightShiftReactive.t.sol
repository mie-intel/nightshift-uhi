// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IReactive} from "@reactive/interfaces/IReactive.sol";
import {AbstractPayer} from "@reactive/base/AbstractPayer.sol";

import {ReactiveFixture} from "../utils/ReactiveFixture.sol";
import {NightShiftReactive} from "../../src/reactive/NightShiftReactive.sol";
import {MockSystemContract} from "../../src/mocks/MockSystemContract.sol";
import {INightShiftController} from "../../src/interfaces/INightShiftController.sol";
import {PriceMath} from "../../src/libraries/PriceMath.sol";
import {GasLimits, Regime, SourceKind, WitnessSource} from "../../src/libraries/Types.sol";
import {NightShiftConfig} from "../../script/utils/NightShiftConfig.sol";

contract NightShiftReactiveTest is ReactiveFixture {
    uint256 satNoon;
    uint256 friOpen;

    function setUp() public {
        satNoon = _utc(2026, 11, 21, 12, 0);
        friOpen = _utc(2026, 11, 20, 20, 0);
        _deployReactive(satNoon);
    }

    /// @dev Issuer at 1.00 (tick 0) on Sepolia + sibling on Base → quorum across 2 chains.
    function _quorumAt(int24 siblingTick) internal {
        _issuerAt(1e18);
        _react(_swapLog(SIBLING_POOL, siblingTick));
    }

    // ---------------------------------------------------------------- setup + admin

    function test_constructor_regimeFromCalendar() public {
        assertEq(uint8(rx.regime()), uint8(Regime.CLOSED));
        vm.warp(friOpen);
        NightShiftReactive r2 = new NightShiftReactive(DEST, destPool, qp, rp, gl, NightShiftConfig.cronTopic(json));
        assertEq(uint8(r2.regime()), uint8(Regime.OPEN));
    }

    function test_constructor_revert_gasTooLow() public {
        GasLimits memory g = gl;
        g.onRegime = 99_999;
        vm.expectRevert(NightShiftReactive.GasTooLow.selector);
        new NightShiftReactive(DEST, destPool, qp, rp, g, NightShiftConfig.cronTopic(json));
    }

    function test_subscriptions_matchSources_andCron() public view {
        assertEq(sys.subCount(), 4);
        MockSystemContract.Sub memory s0 = sys.subAt(0);
        assertEq(s0.chainId, ORIGIN);
        assertEq(s0.emitter, issuer);
        assertEq(s0.topic0, rx.MINTED_TOPIC0());
        assertEq(s0.topic1, REACTIVE_IGNORE);
        MockSystemContract.Sub memory s1 = sys.subAt(1);
        assertEq(s1.topic0, rx.V4_SWAP_TOPIC0());
        assertEq(s1.topic1, uint256(SIBLING_POOL), "sibling filtered by poolId");
        MockSystemContract.Sub memory cron = sys.subAt(3);
        assertEq(cron.chainId, block.chainid);
        assertEq(cron.emitter, rx.CRON_EMITTER());
        assertEq(cron.topic0, rx.cronTopic());
        assertEq(rx.cronTopic(), 0xe20b31294d84c3661ddc8f423abb9c70310d0cf172aa2714ead78029b325e3f4, "Cron1000");
    }

    function test_admin_onlyOwner() public {
        WitnessSource memory s = _source(ORIGIN, issuer, 1, REACTIVE_IGNORE, SourceKind.ORACLE, 1);
        vm.startPrank(makeAddr("rando"));
        vm.expectRevert(NightShiftReactive.NotOwner.selector);
        rx.addSource(s);
        vm.expectRevert(NightShiftReactive.NotOwner.selector);
        rx.setController(address(1));
        vm.expectRevert(NightShiftReactive.NotOwner.selector);
        rx.subscribeCron();
        vm.expectRevert(NightShiftReactive.NotOwner.selector);
        rx.setPaused(true);
        vm.stopPrank();
    }

    function test_addSource_capped() public {
        WitnessSource memory s = _source(ORIGIN, issuer, 1, REACTIVE_IGNORE, SourceKind.ORACLE, 1);
        for (uint256 i = rx.sourceCount(); i < rx.MAX_SOURCES(); i++) {
            rx.addSource(s);
        }
        vm.expectRevert(NightShiftReactive.TooManySources.selector);
        rx.addSource(s);
    }

    function test_disableSource_ignoresItsLogs() public {
        rx.disableSource(I_ISSUER);
        assertEq(sys.unsubCount(), 1);
        IReactive.LogRecord memory l = _issuerLog(1e18, 1e18);
        vm.prank(SYSTEM_ADDR);
        vm.expectRevert(NightShiftReactive.UnexpectedLog.selector);
        rx.react(l);
    }

    function test_withdraw_onlyOwner() public {
        vm.deal(address(rx), 1 ether);
        address payable to = payable(makeAddr("to"));
        vm.prank(makeAddr("rando"));
        vm.expectRevert(NightShiftReactive.NotOwner.selector);
        rx.withdraw(to, 1 ether);
        rx.withdraw(to, 0.4 ether);
        assertEq(to.balance, 0.4 ether);
    }

    // ---------------------------------------------------------------- react guards

    function test_react_onlySystem() public {
        IReactive.LogRecord memory l = _issuerLog(1e18, 1e18);
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), SYSTEM_ADDR));
        rx.react(l);
    }

    function test_react_revert_controllerNotSet() public {
        NightShiftReactive r2 = new NightShiftReactive(DEST, destPool, qp, rp, gl, NightShiftConfig.cronTopic(json));
        IReactive.LogRecord memory l = _issuerLog(1e18, 1e18);
        vm.prank(SYSTEM_ADDR);
        vm.expectRevert(NightShiftReactive.ControllerNotSet.selector);
        r2.react(l);
    }

    function test_react_revert_unexpectedLog() public {
        IReactive.LogRecord memory l = _swapLog(bytes32(uint256(0xbad)), 0); // unknown pool id
        vm.prank(SYSTEM_ADDR);
        vm.expectRevert(NightShiftReactive.UnexpectedLog.selector);
        rx.react(l);
    }

    function test_react_paused_ignores() public {
        rx.setPaused(true);
        _quorumAt(10);
        assertFalse(rx.hasAnchor());
        assertEq(sys.queueLength(), 0);
    }

    // ---------------------------------------------------------------- quorum (README §7.5)

    function test_singleChain_noQuorum_noCallback() public {
        _issuerAt(1.02e18); // weight 5 >= 4, but only one chain
        assertFalse(rx.quorum());
        assertFalse(rx.hasAnchor());
        assertEq(sys.queueLength(), 0);
    }

    function test_twoChains_quorum_sendsAnchor_issuerOutweighsSibling() public {
        _issuerAt(1.02e18); // tick ~198
        _react(_swapLog(SIBLING_POOL, 0)); // sibling disagrees at tick 0
        int24 issuerTick = PriceMath.tickFromRatio(1.02e18, 1e18);
        assertTrue(rx.quorum());
        assertEq(rx.anchor(), issuerTick, "weighted median picks the heavier issuer");
        assertEq(rx.dispersion(), uint16(uint24(issuerTick)) * 2 / 7, "MAD = 2/7 of the gap");
        assertEq(sys.queueLength(), 1);
        bytes memory expected = abi.encodeWithSelector(
            INightShiftController.onAnchor.selector,
            address(0),
            destPool,
            uint64(1),
            issuerTick,
            rx.riskBps(),
            rx.dispersion(),
            uint8(2),
            uint40(block.timestamp)
        );
        MockSystemContract.Queued memory q = sys.queuedAt(0);
        assertEq(q.config.payload, expected);
        assertEq(q.config.chainId, DEST);
        assertEq(q.config.recipient, controllerAddr);
        assertEq(q.config.gasLimit, gl.onAnchor);
    }

    function test_selfSwaps_neverInAnchor() public {
        _issuerAt(1e18);
        _react(_swapLog(destPool, 5000)); // own pool far away
        assertFalse(rx.quorum(), "SELF does not count toward quorum");
        assertTrue(rx.hasSelf());
        assertEq(rx.selfTick(), 5000);
    }

    // ---------------------------------------------------------------- smoothing + caps (README §7.4)

    function test_influenceCap_clampsOutlier() public {
        _quorumAt(0);
        vm.warp(block.timestamp + 1 days); // full EWMA weight on the next print
        _react(_swapLog(SIBLING_POOL, 50_000)); // manipulated sibling
        (, NightShiftReactive.SourceState memory st) = rx.sourceAt(I_SIBLING);
        assertEq(st.lastRaw, 50_000);
        assertLe(st.ewma, int24(qp.maxJumpTicks), "clamped to anchor + maxJump");
    }

    function test_ewma_halfLife() public {
        _quorumAt(0);
        vm.warp(block.timestamp + qp.halfLifeSeconds);
        _react(_swapLog(SIBLING_POOL, 200)); // within the jump cap
        (, NightShiftReactive.SourceState memory st) = rx.sourceAt(I_SIBLING);
        assertApproxEqAbs(int256(st.ewma), 100, 1, "half-life moves halfway");
    }

    /// @dev S6: one manipulated sibling cannot move the anchor (issuer outweighs it).
    function test_manipulatedSibling_anchorUnchanged() public {
        _quorumAt(0);
        int24 before = rx.anchor();
        for (uint256 i; i < 5; i++) {
            vm.warp(block.timestamp + 10 minutes);
            _react(_swapLog(SIBLING_POOL, 50_000));
        }
        assertEq(rx.anchor(), before);
    }

    // ---------------------------------------------------------------- debounce (README §7.6)

    function test_debounce_smallMove_noCallback_untilHeartbeat() public {
        _quorumAt(0);
        assertEq(sys.queueLength(), 1);
        vm.warp(block.timestamp + 2 minutes);
        _issuerAt(1.0005e18); // ~5 ticks < minAnchorDelta
        assertEq(sys.queueLength(), 1, "below minAnchorDelta");
        vm.warp(block.timestamp + qp.heartbeatSeconds);
        _issuerAt(1.0005e18);
        _react(_swapLog(SIBLING_POOL, 0));
        assertEq(sys.queueLength(), 2, "heartbeat forces an update");
    }

    function test_debounce_minInterval() public {
        _quorumAt(0);
        _issuerAt(1.05e18); // big move but same second
        assertEq(sys.queueLength(), 1, "min interval holds");
        vm.warp(block.timestamp + qp.minCallbackIntervalSeconds);
        _issuerAt(1.05e18);
        assertEq(sys.queueLength(), 2);
    }

    function test_seq_strictlyIncreasing() public {
        _quorumAt(0);
        for (uint256 i = 1; i <= 3; i++) {
            vm.warp(block.timestamp + 5 minutes);
            _issuerAt(1e18 + i * 0.01e18);
        }
        assertEq(rx.seq(), sys.queueLength());
        assertEq(rx.seq(), 4);
    }

    // ---------------------------------------------------------------- risk (README §8)

    function test_staleness_dropsQuorum_riskKeepsRising() public {
        _quorumAt(0);
        uint16 r0 = rx.riskBps();
        int24 a0 = rx.anchor();
        vm.warp(block.timestamp + 7 hours); // > maxAgeClosed (6h)
        _react(_cronLog());
        assertFalse(rx.quorum(), "stale witnesses -> no quorum");
        assertGt(rx.riskBps(), r0, "time + staleness raise risk");
        assertEq(rx.anchor(), a0, "anchor frozen without quorum");
    }

    function test_closed_riskNeverDecreases_acrossCron() public {
        _quorumAt(0);
        _react(_swapLog(destPool, 250)); // own pool diverges
        uint16 prev = rx.riskBps();
        _react(_swapLog(destPool, 0)); // divergence back to 0 — must not lower risk while CLOSED
        assertGe(rx.riskBps(), prev);
        for (uint256 i; i < 10; i++) {
            vm.warp(block.timestamp + 2 minutes);
            _react(_cronLog());
            assertGe(rx.riskBps(), prev);
            prev = rx.riskBps();
        }
    }

    function test_selfDivergence_raisesRisk() public {
        _quorumAt(0);
        uint16 before = rx.riskBps();
        _react(_swapLog(destPool, int24(rp.divergenceFullTicks)));
        assertGe(rx.riskBps(), before + rp.weightDivergence - 1);
    }

    // ---------------------------------------------------------------- regime on Cron (README §6.3, §7.7)

    function test_cron_fullCycle_close_reopen_reconcile() public {
        vm.warp(friOpen);
        NightShiftReactive r = new NightShiftReactive(DEST, destPool, qp, rp, gl, NightShiftConfig.cronTopic(json));
        r.addSource(_source(ORIGIN, issuer, r.MINTED_TOPIC0(), REACTIVE_IGNORE, SourceKind.ISSUER_MINT, 5));
        r.addSource(_source(DEST, destPm, r.V4_SWAP_TOPIC0(), uint256(SIBLING_POOL), SourceKind.V4_SWAP, 2));
        r.setController(controllerAddr);
        rx = r;
        uint256 q0 = sys.queueLength();

        // Fri 21:00 UTC close
        vm.warp(_utc(2026, 11, 20, 21, 0));
        _react(_cronLog());
        assertEq(uint8(rx.regime()), uint8(Regime.CLOSED));
        assertEq(rx.epochId(), 1);
        assertEq(_selector(q0), INightShiftController.onRegime.selector);

        // Mon 14:30 UTC open → REOPEN_PENDING
        vm.warp(_utc(2026, 11, 23, 14, 30));
        _react(_cronLog());
        assertEq(uint8(rx.regime()), uint8(Regime.REOPEN_PENDING));
        assertEq(_selector(q0 + 1), INightShiftController.onRegime.selector);

        // witnesses inside the open window
        vm.warp(block.timestamp + 5 minutes);
        _quorumAt(30);
        uint16 closedRisk = rx.riskBps(); // ratcheted over the whole weekend
        // window closes → reconcile with quorum → OPEN; ratchet resets, risk follows raw (dispersion only)
        vm.warp(_utc(2026, 11, 23, 14, 45));
        _react(_cronLog());
        assertEq(uint8(rx.regime()), uint8(Regime.OPEN));
        assertGt(closedRisk, 3000, "weekend time component near full");
        assertLe(rx.riskBps(), rp.weightDispersion, "only witness dispersion remains");
        bool sawReconcile;
        for (uint256 i = q0 + 2; i < sys.queueLength(); i++) {
            if (_selector(i) == INightShiftController.onReconcile.selector) sawReconcile = true;
        }
        assertTrue(sawReconcile);
    }

    function test_cron_degradedReconcile_afterTimeout() public {
        vm.warp(_utc(2026, 11, 23, 14, 30));
        _react(_cronLog()); // CLOSED → REOPEN_PENDING (no witnesses at all)
        assertEq(uint8(rx.regime()), uint8(Regime.REOPEN_PENDING));
        vm.warp(block.timestamp + qp.openWindowSeconds);
        _react(_cronLog());
        assertEq(uint8(rx.regime()), uint8(Regime.REOPEN_PENDING), "no quorum: wait for timeout");
        vm.warp(_utc(2026, 11, 23, 14, 30) + qp.reconcileTimeoutSeconds);
        _react(_cronLog());
        assertEq(uint8(rx.regime()), uint8(Regime.OPEN), "degraded reconcile");
        bytes memory p = sys.queuedAt(sys.queueLength() - 1).config.payload;
        assertEq(p[p.length - 1], bytes1(0x01), "degraded flag set");
    }

    function test_cron_noTransition_whileClosed() public {
        uint256 q0 = sys.queueLength();
        vm.warp(block.timestamp + 2 minutes);
        _react(_cronLog());
        assertEq(uint8(rx.regime()), uint8(Regime.CLOSED));
        assertEq(sys.queueLength(), q0, "no quorum -> nothing to send");
    }

    // ---------------------------------------------------------------- gas (README §13.2: react < 900k)

    function test_gas_maxSources_underReactiveCap() public {
        for (uint256 i = rx.sourceCount(); i < rx.MAX_SOURCES(); i++) {
            rx.addSource(
                _source(DEST, destPm, rx.V4_SWAP_TOPIC0(), uint256(keccak256(abi.encode(i))), SourceKind.V4_SWAP, 2)
            );
        }
        for (uint256 i = 3; i < rx.MAX_SOURCES(); i++) {
            _react(_swapLog(keccak256(abi.encode(i)), int24(int256(i * 7))));
        }
        _issuerAt(1e18);
        IReactive.LogRecord memory l = _swapLog(SIBLING_POOL, 3);
        vm.prank(SYSTEM_ADDR);
        uint256 g = gasleft();
        rx.react(l);
        uint256 used = g - gasleft();
        emit log_named_uint("react() gas @16 sources", used);
        assertLt(used, 900_000);
    }
}
