// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {NyseCalendar} from "../../src/libraries/NyseCalendar.sol";
import {Regime} from "../../src/libraries/Types.sol";

contract NyseCalendarHarness {
    function isOpen(uint256 ts) external pure returns (bool) {
        return NyseCalendar.isOpen(ts);
    }

    function regimeAt(uint256 ts) external pure returns (Regime) {
        return NyseCalendar.regimeAt(ts);
    }

    function civil(uint256 days_) external pure returns (uint256, uint256, uint256) {
        return NyseCalendar.civilFromDays(days_);
    }

    function fromCivil(uint256 y, uint256 m, uint256 d) external pure returns (uint256) {
        return NyseCalendar.daysFromCivil(y, m, d);
    }
}

/// @notice Reference data is an INDEPENDENT hand-written table (official NYSE 2026–2027 schedule + US DST dates),
///         not derived from the library's rules.
contract NyseCalendarTest is Test {
    NyseCalendarHarness h;

    uint256 constant EPOCH_DAY_2026_01_01 = 20_454; // 56·365 + 14 leap days
    uint256 constant EPOCH_DAY_2027_01_01 = 20_819;

    function setUp() public {
        h = new NyseCalendarHarness();
    }

    // ---------- independent reference helpers ----------

    function _cum(uint256 m, bool leap) internal pure returns (uint256) {
        uint16[12] memory c = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
        return c[m - 1] + (leap && m > 2 ? 1 : 0);
    }

    /// @dev Days since epoch for 2026/2027 dates only (neither is a leap year).
    function _day(uint256 y, uint256 m, uint256 d) internal pure returns (uint256) {
        uint256 base = y == 2026 ? EPOCH_DAY_2026_01_01 : EPOCH_DAY_2027_01_01;
        return base + _cum(m, false) + d - 1;
    }

    /// @dev UTC timestamp for a NYSE-local (ET) time on a 2026/2027 date, using the hand-entered DST table.
    function _et(uint256 y, uint256 m, uint256 d, uint256 hh, uint256 mm) internal pure returns (uint256) {
        uint256 dayStart = _day(y, m, d) * 1 days;
        uint256 localSec = hh * 1 hours + mm * 1 minutes;
        uint256 utcGuess = dayStart + localSec + 5 hours;
        return _inDst(utcGuess - 1 hours) ? utcGuess - 1 hours : utcGuess;
    }

    /// @dev DST 2026: Mar 8 07:00 UTC → Nov 1 06:00 UTC. DST 2027: Mar 14 07:00 UTC → Nov 7 06:00 UTC.
    function _inDst(uint256 ts) internal pure returns (bool) {
        return (ts >= _day(2026, 3, 8) * 1 days + 7 hours && ts < _day(2026, 11, 1) * 1 days + 6 hours)
            || (ts >= _day(2027, 3, 14) * 1 days + 7 hours && ts < _day(2027, 11, 7) * 1 days + 6 hours);
    }

    function _holidays() internal pure returns (uint256[20] memory hs) {
        hs = [
            // 2026
            _day(2026, 1, 1),
            _day(2026, 1, 19),
            _day(2026, 2, 16),
            _day(2026, 4, 3),
            _day(2026, 5, 25),
            _day(2026, 6, 19),
            _day(2026, 7, 3),
            _day(2026, 9, 7),
            _day(2026, 11, 26),
            _day(2026, 12, 25),
            // 2027
            _day(2027, 1, 1),
            _day(2027, 1, 18),
            _day(2027, 2, 15),
            _day(2027, 3, 26),
            _day(2027, 5, 31),
            _day(2027, 6, 18),
            _day(2027, 7, 5),
            _day(2027, 9, 6),
            _day(2027, 11, 25),
            _day(2027, 12, 24)
        ];
    }

    function _earlyCloses() internal pure returns (uint256[3] memory es) {
        es = [_day(2026, 11, 27), _day(2026, 12, 24), _day(2027, 11, 26)];
    }

    function _refOpen(uint256 ts) internal pure returns (bool) {
        return _refOpen(ts, _holidays(), _earlyCloses());
    }

    function _refOpen(uint256 ts, uint256[20] memory hs, uint256[3] memory es) internal pure returns (bool) {
        uint256 local = ts - (_inDst(ts) ? 4 hours : 5 hours);
        uint256 day = local / 1 days;
        uint256 sec = local % 1 days;
        uint256 dow = (day + 4) % 7;
        if (dow == 0 || dow == 6) return false;
        for (uint256 i; i < hs.length; i++) {
            if (hs[i] == day) return false;
        }
        uint256 close = 16 hours;
        for (uint256 i; i < es.length; i++) {
            if (es[i] == day) close = 13 hours;
        }
        return sec >= 9 hours + 30 minutes && sec < close;
    }

    // ---------- date helpers ----------

    function test_epochAnchors() public view {
        assertEq(h.fromCivil(2026, 1, 1), EPOCH_DAY_2026_01_01);
        assertEq(h.fromCivil(2027, 1, 1), EPOCH_DAY_2027_01_01);
        assertEq(h.fromCivil(1970, 1, 1), 0);
        (uint256 y, uint256 m, uint256 d) = h.civil(_day(2026, 11, 26));
        assertEq(y * 10_000 + m * 100 + d, 20_261_126);
    }

    function testFuzz_civilRoundTrip(uint256 z) public view {
        z = bound(z, 0, 200 * 366);
        (uint256 y, uint256 m, uint256 d) = h.civil(z);
        assertEq(h.fromCivil(y, m, d), z);
    }

    // ---------- every 2026–2027 holiday is closed mid-session ----------

    function test_allHolidays_closed() public view {
        uint256[20] memory hs = _holidays();
        for (uint256 i; i < hs.length; i++) {
            uint256 noonUtc = hs[i] * 1 days + 17 hours; // 12:00/13:00 ET
            assertFalse(h.isOpen(noonUtc), "holiday open");
        }
    }

    /// @dev Spec checkpoint: Thanksgiving 26 Nov 2026 closed all day.
    function test_thanksgiving2026_closed() public view {
        assertFalse(h.isOpen(_et(2026, 11, 26, 9, 30)));
        assertFalse(h.isOpen(_et(2026, 11, 26, 12, 0)));
        assertEq(uint8(h.regimeAt(_et(2026, 11, 26, 12, 0))), uint8(Regime.CLOSED));
    }

    /// @dev Spec checkpoint: Black Friday 27 Nov 2026 open 14:30–18:00 UTC.
    function test_blackFriday2026_earlyClose18utc() public view {
        uint256 d = _day(2026, 11, 27) * 1 days;
        assertFalse(h.isOpen(d + 14 hours + 29 minutes));
        assertTrue(h.isOpen(d + 14 hours + 30 minutes));
        assertTrue(h.isOpen(d + 17 hours + 59 minutes));
        assertFalse(h.isOpen(d + 18 hours));
        assertEq(uint8(h.regimeAt(d + 15 hours)), uint8(Regime.OPEN));
    }

    function test_christmasEve2026_earlyClose() public view {
        assertTrue(h.isOpen(_et(2026, 12, 24, 12, 59)));
        assertFalse(h.isOpen(_et(2026, 12, 24, 13, 0)));
    }

    /// @dev 2027: Christmas on Saturday -> observed Fri 24 Dec (closed, not early close).
    function test_christmas2027_observedFriday() public view {
        assertFalse(h.isOpen(_et(2027, 12, 24, 10, 0)));
        assertTrue(h.isOpen(_et(2027, 12, 27, 10, 0)));
    }

    /// @dev 2026: July 4 is Saturday -> Fri 3 Jul closed, Thu 2 Jul is a full session.
    function test_july2026() public view {
        assertFalse(h.isOpen(_et(2026, 7, 3, 10, 0)));
        assertTrue(h.isOpen(_et(2026, 7, 2, 15, 59)));
    }

    /// @dev Jan 1 2028 is Saturday: NYSE does NOT observe on Fri 31 Dec 2027.
    function test_newYear2028_saturdayNotObserved() public view {
        uint256 d = NyseCalendar.daysFromCivil(2027, 12, 31) * 1 days;
        assertTrue(h.isOpen(d + 15 hours)); // 10:00 EST
    }

    // ---------- session boundaries + DST ----------

    function test_sessionBoundaries_EST() public view {
        // Mon 23 Nov 2026 (EST): 14:30–21:00 UTC
        uint256 d = _day(2026, 11, 23) * 1 days;
        assertFalse(h.isOpen(d + 14 hours + 29 minutes + 59));
        assertTrue(h.isOpen(d + 14 hours + 30 minutes));
        assertTrue(h.isOpen(d + 20 hours + 59 minutes + 59));
        assertFalse(h.isOpen(d + 21 hours));
    }

    function test_dstStart2026() public view {
        // Fri 6 Mar (EST): 13:30 UTC = 08:30 ET closed; Mon 9 Mar (EDT): 13:30 UTC = 09:30 ET open
        assertFalse(h.isOpen(_day(2026, 3, 6) * 1 days + 13 hours + 30 minutes));
        assertTrue(h.isOpen(_day(2026, 3, 9) * 1 days + 13 hours + 30 minutes));
        assertFalse(h.isOpen(_day(2026, 3, 9) * 1 days + 20 hours)); // 16:00 EDT
    }

    function test_dstEnd2026() public view {
        // Fri 30 Oct (EDT): 13:30 UTC open; Mon 2 Nov (EST): 13:30 UTC closed, 14:30 open
        assertTrue(h.isOpen(_day(2026, 10, 30) * 1 days + 13 hours + 30 minutes));
        assertFalse(h.isOpen(_day(2026, 11, 2) * 1 days + 13 hours + 30 minutes));
        assertTrue(h.isOpen(_day(2026, 11, 2) * 1 days + 14 hours + 30 minutes));
    }

    function test_weekend_closed() public view {
        assertFalse(h.isOpen(_et(2026, 11, 21, 12, 0))); // Sat
        assertFalse(h.isOpen(_et(2026, 11, 22, 12, 0))); // Sun
    }

    // ---------- fuzz vs independent reference table ----------

    function testFuzz_isOpen_matchesReference(uint256 ts) public view {
        ts = bound(ts, EPOCH_DAY_2026_01_01 * 1 days + 1 days, (EPOCH_DAY_2027_01_01 + 364) * 1 days);
        assertEq(h.isOpen(ts), _refOpen(ts));
    }

    /// @dev Exhaustive daily sweep at session-sensitive times (09:29, 09:30, 12:59, 13:00, 15:59, 16:00 ET).
    function test_sweep_2026_2027() public view {
        uint256[6] memory mins = [uint256(569), 570, 779, 780, 959, 960];
        uint256[20] memory hs = _holidays();
        uint256[3] memory es = _earlyCloses();
        for (uint256 day = EPOCH_DAY_2026_01_01; day < EPOCH_DAY_2027_01_01 + 365; day++) {
            for (uint256 k; k < mins.length; k++) {
                uint256 utcEst = day * 1 days + mins[k] * 1 minutes + 5 hours;
                uint256 ts = _inDst(utcEst - 1 hours) ? utcEst - 1 hours : utcEst;
                assertEq(h.isOpen(ts), _refOpen(ts, hs, es));
            }
        }
    }
}
