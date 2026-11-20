/**
 * NYSE regular-session calendar — a direct port of contracts/src/libraries/NyseCalendar.sol (same rules, same
 * results), so the dashboard shows exactly what the contracts compute. Times are unix seconds (UTC).
 */
const DAY = 86_400;
const OPEN_SEC = 9 * 3600 + 30 * 60;
const CLOSE_SEC = 16 * 3600;
const EARLY_SEC = 13 * 3600;
const MON = 1;
const THU = 4;
const FRI = 5;

export const weekday = (days: number) => (days + 4) % 7; // 1970-01-01 = Thursday; 0 = Sunday

export function daysFromCivil(y: number, m: number, d: number): number {
  if (m <= 2) y -= 1;
  const era = Math.floor(y / 400);
  const yoe = y - era * 400;
  const mp = m > 2 ? m - 3 : m + 9;
  const doy = Math.floor((153 * mp + 2) / 5) + d - 1;
  const doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
  return era * 146_097 + doe - 719_468;
}

export function civilFromDays(z: number): [number, number, number] {
  z += 719_468;
  const era = Math.floor(z / 146_097);
  const doe = z - era * 146_097;
  const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36_524) - Math.floor(doe / 146_096)) / 365);
  const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
  const mp = Math.floor((5 * doy + 2) / 153);
  const d = doy - Math.floor((153 * mp + 2) / 5) + 1;
  const m = mp < 10 ? mp + 3 : mp - 9;
  return [yoe + era * 400 + (m <= 2 ? 1 : 0), m, d];
}

const nthWeekday = (y: number, m: number, dow: number, n: number) => {
  const first = daysFromCivil(y, m, 1);
  return first + ((dow + 7 - weekday(first)) % 7) + 7 * (n - 1);
};

const lastMondayOfMay = (y: number) => {
  const last = daysFromCivil(y, 5, 31);
  return last - ((weekday(last) + 7 - MON) % 7);
};

function easter(y: number): number {
  const a = y % 19, b = Math.floor(y / 100), c = y % 100;
  const h = (19 * a + b - Math.floor(b / 4) - Math.floor((8 * b + 13) / 25) + 15) % 30;
  const l = (32 + 2 * (b % 4) + 2 * Math.floor(c / 4) - h - (c % 4)) % 7;
  const mm = Math.floor((a + 11 * h + 19 * l) / 433);
  const month = Math.floor((h + l - 7 * mm + 90) / 25);
  const day = (h + l - 7 * mm + 33 * month + 19) % 32;
  return daysFromCivil(y, month, day);
}

function isHoliday(y: number, m: number, d: number, days: number): boolean {
  const dow = weekday(days);
  if (m === 1) return d === 1 || (d === 2 && dow === MON) || days === nthWeekday(y, 1, MON, 3);
  if (m === 2) return days === nthWeekday(y, 2, MON, 3);
  if (m === 3 || m === 4) return days + 2 === easter(y);
  if (m === 5) return days === lastMondayOfMay(y);
  if (m === 6) return d === 19 || (d === 18 && dow === FRI) || (d === 20 && dow === MON);
  if (m === 7) return d === 4 || (d === 3 && dow === FRI) || (d === 5 && dow === MON);
  if (m === 9) return days === nthWeekday(y, 9, MON, 1);
  if (m === 11) return days === nthWeekday(y, 11, THU, 4);
  if (m === 12) return d === 25 || (d === 24 && dow === FRI) || (d === 26 && dow === MON);
  return false;
}

function isEarlyClose(y: number, m: number, d: number, days: number): boolean {
  const dow = weekday(days);
  if (m === 7) return d === 3 && dow >= MON && dow <= THU;
  if (m === 11) return days === nthWeekday(y, 11, THU, 4) + 1;
  if (m === 12) return d === 24 && dow >= MON && dow <= THU;
  return false;
}

export function isDst(ts: number): boolean {
  const [y] = civilFromDays(Math.floor(ts / DAY));
  const start = nthWeekday(y, 3, 0, 2) * DAY + 7 * 3600;
  const end = nthWeekday(y, 11, 0, 1) * DAY + 6 * 3600;
  return ts >= start && ts < end;
}

export function isOpen(ts: number): boolean {
  const local = ts - (isDst(ts) ? 4 : 5) * 3600;
  const day = Math.floor(local / DAY);
  const sec = local % DAY;
  const dow = weekday(day);
  if (dow === 0 || dow === 6) return false;
  const [y, m, d] = civilFromDays(day);
  if (isHoliday(y, m, d, day)) return false;
  const close = isEarlyClose(y, m, d, day) ? EARLY_SEC : CLOSE_SEC;
  return sec >= OPEN_SEC && sec < close;
}

/** Next open/close transition after `ts` (minute resolution, up to 10 days ahead). */
export function nextTransition(ts: number): number | null {
  const now = isOpen(ts);
  const start = ts - (ts % 60) + 60;
  for (let t = start; t < ts + 10 * DAY; t += 60) if (isOpen(t) !== now) return t;
  return null;
}

/** Why the market is closed right now (for a friendly label). */
export function closedReason(ts: number): string {
  const local = ts - (isDst(ts) ? 4 : 5) * 3600;
  const day = Math.floor(local / DAY);
  const dow = weekday(day);
  if (dow === 0 || dow === 6) return "Weekend";
  const [y, m, d] = civilFromDays(day);
  if (isHoliday(y, m, d, day)) return "Holiday";
  return "After hours";
}
