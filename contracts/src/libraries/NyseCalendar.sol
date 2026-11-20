// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Regime} from "./Types.sol";

/// @title NyseCalendar
/// @notice Rule-based NYSE regular-session calendar (SPEC §6.2): US Eastern time with DST, weekends, full-day
///         holidays with weekend observance, and 13:00 ET early closes. Pure; used by NightShiftReactive (Cron) and
///         NightShiftController (`syncRegime` fallback).
/// @dev Rules follow the published NYSE holiday rules; approach informed by Gapguard (Bytethebuilder, MIT) and
///      horsefacts/trading-days (MIT). Valid for 2022+ (Juneteenth). Unscheduled closures are handled by the
///      timelocked override list in the consuming contract, not here.
///      Rules: New Year's (Sun→Mon; Sat→not observed) · MLK 3rd Mon Jan · Presidents 3rd Mon Feb · Good Friday ·
///      Memorial last Mon May · Juneteenth · Independence · Labor 1st Mon Sep · Thanksgiving 4th Thu Nov ·
///      Christmas (Sat→Fri, Sun→Mon). Early close 13:00 ET: Jul 3 (Mon–Thu), day after Thanksgiving,
///      Dec 24 (Mon–Thu).
library NyseCalendar {
    uint256 private constant DAY = 1 days;
    uint256 private constant OPEN_SEC = 9 hours + 30 minutes;
    uint256 private constant CLOSE_SEC = 16 hours;
    uint256 private constant EARLY_CLOSE_SEC = 13 hours;

    // weekday numbering: 0 = Sunday … 6 = Saturday
    uint256 private constant MON = 1;
    uint256 private constant THU = 4;
    uint256 private constant FRI = 5;

    /// @notice OPEN during a regular session, else CLOSED. (REOPEN_PENDING/HALTED are protocol states, not calendar.)
    function regimeAt(uint256 ts) internal pure returns (Regime) {
        return isOpen(ts) ? Regime.OPEN : Regime.CLOSED;
    }

    /// @notice True iff `ts` (unix seconds) falls inside an NYSE regular session.
    function isOpen(uint256 ts) internal pure returns (bool) {
        uint256 local = ts - (isDst(ts) ? 4 hours : 5 hours);
        uint256 day = local / DAY;
        uint256 sec = local % DAY;
        uint256 dow = weekday(day);
        if (dow == 0 || dow == 6) return false;
        (uint256 y, uint256 m, uint256 d) = civilFromDays(day);
        if (isHoliday(y, m, d, day)) return false;
        uint256 close = isEarlyClose(y, m, d, day) ? EARLY_CLOSE_SEC : CLOSE_SEC;
        return sec >= OPEN_SEC && sec < close;
    }

    /// @notice US DST: second Sunday of March 07:00 UTC (02:00 EST) → first Sunday of November 06:00 UTC (02:00 EDT).
    function isDst(uint256 ts) internal pure returns (bool) {
        (uint256 y,,) = civilFromDays(ts / DAY);
        uint256 start = nthWeekday(y, 3, 0, 2) * DAY + 7 hours;
        uint256 end = nthWeekday(y, 11, 0, 1) * DAY + 6 hours;
        return ts >= start && ts < end;
    }

    /// @notice Full-day NYSE holiday on weekday `days` (days since epoch) = (y, m, d).
    function isHoliday(uint256 y, uint256 m, uint256 d, uint256 days_) internal pure returns (bool) {
        uint256 dow = weekday(days_);
        if (m == 1) return d == 1 || (d == 2 && dow == MON) || days_ == nthWeekday(y, 1, MON, 3);
        if (m == 2) return days_ == nthWeekday(y, 2, MON, 3);
        if (m == 3 || m == 4) return days_ + 2 == easter(y);
        if (m == 5) return days_ == lastMondayOfMay(y);
        if (m == 6) return d == 19 || (d == 18 && dow == FRI) || (d == 20 && dow == MON);
        if (m == 7) return d == 4 || (d == 3 && dow == FRI) || (d == 5 && dow == MON);
        if (m == 9) return days_ == nthWeekday(y, 9, MON, 1);
        if (m == 11) return days_ == nthWeekday(y, 11, THU, 4);
        if (m == 12) return d == 25 || (d == 24 && dow == FRI) || (d == 26 && dow == MON);
        return false;
    }

    /// @notice 13:00 ET early close on a (non-holiday) weekday.
    function isEarlyClose(uint256 y, uint256 m, uint256 d, uint256 days_) internal pure returns (bool) {
        uint256 dow = weekday(days_);
        if (m == 7) return d == 3 && dow >= MON && dow <= THU;
        if (m == 11) return days_ == nthWeekday(y, 11, THU, 4) + 1;
        if (m == 12) return d == 24 && dow >= MON && dow <= THU;
        return false;
    }

    /// @notice Day of week for days since epoch (1970-01-01 was a Thursday). 0 = Sunday.
    function weekday(uint256 days_) internal pure returns (uint256) {
        return (days_ + 4) % 7;
    }

    /// @notice Days since epoch of the `n`-th `dow` weekday in month `m` of year `y`.
    function nthWeekday(uint256 y, uint256 m, uint256 dow, uint256 n) internal pure returns (uint256) {
        uint256 first = daysFromCivil(y, m, 1);
        return first + (dow + 7 - weekday(first)) % 7 + 7 * (n - 1);
    }

    /// @notice Days since epoch of the last Monday of May.
    function lastMondayOfMay(uint256 y) internal pure returns (uint256) {
        uint256 last = daysFromCivil(y, 5, 31);
        return last - (weekday(last) + 7 - MON) % 7;
    }

    /// @notice Days since epoch of Easter Sunday (anonymous Gregorian algorithm).
    function easter(uint256 y) internal pure returns (uint256) {
        uint256 a = y % 19;
        uint256 b = y / 100;
        uint256 c = y % 100;
        uint256 h = (19 * a + b - b / 4 - (8 * b + 13) / 25 + 15) % 30;
        uint256 l = (32 + 2 * (b % 4) + 2 * (c / 4) - h - c % 4) % 7;
        uint256 mm = (a + 11 * h + 19 * l) / 433;
        uint256 month = (h + l - 7 * mm + 90) / 25;
        uint256 day = (h + l - 7 * mm + 33 * month + 19) % 32;
        return daysFromCivil(y, month, day);
    }

    /// @notice Days since 1970-01-01 for a Gregorian date (Hinnant's algorithm, years >= 1970).
    function daysFromCivil(uint256 y, uint256 m, uint256 d) internal pure returns (uint256) {
        if (m <= 2) y -= 1;
        uint256 era = y / 400;
        uint256 yoe = y - era * 400;
        uint256 mp = m > 2 ? m - 3 : m + 9;
        uint256 doy = (153 * mp + 2) / 5 + d - 1;
        uint256 doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        return era * 146_097 + doe - 719_468;
    }

    /// @notice Gregorian date for days since 1970-01-01 (Hinnant's algorithm).
    function civilFromDays(uint256 z) internal pure returns (uint256 y, uint256 m, uint256 d) {
        z += 719_468;
        uint256 era = z / 146_097;
        uint256 doe = z - era * 146_097;
        uint256 yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        d = doy - (153 * mp + 2) / 5 + 1;
        m = mp < 10 ? mp + 3 : mp - 9;
        y = yoe + era * 400 + (m <= 2 ? 1 : 0);
    }
}
