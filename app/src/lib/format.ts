import { DEC, D } from "./config";

/** dUSD per dSTOCK for a destination-pool tick (tick = log1.0001(currency1/currency0) in raw units). */
export function tickToPrice(tick: number): number {
  const raw = Math.pow(1.0001, D.invert ? -tick : tick); // raw dUSD per raw dSTOCK
  return raw * Math.pow(10, DEC.stock - DEC.usd);
}

export const usd = (n: number, digits = 2) =>
  n.toLocaleString("en-US", { minimumFractionDigits: digits, maximumFractionDigits: digits });

/** Fee in pips (1e6 = 100%) → "0.30%". */
export const pct = (pips: number) => `${(pips / 10_000).toFixed(2)}%`;

export const signedPct = (x: number) => `${x >= 0 ? "+" : ""}${(x * 100).toFixed(2)}%`;

export const short = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;

export function ago(sec: number): string {
  if (sec < 60) return `${Math.max(0, Math.floor(sec))}s ago`;
  if (sec < 3600) return `${Math.floor(sec / 60)}m ago`;
  if (sec < 86_400) return `${Math.floor(sec / 3600)}h ${Math.floor((sec % 3600) / 60)}m ago`;
  return `${Math.floor(sec / 86_400)}d ago`;
}

export function duration(sec: number): string {
  const d = Math.floor(sec / 86_400);
  const h = Math.floor((sec % 86_400) / 3600);
  const m = Math.floor((sec % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

export const REGIMES = ["Open", "Closed", "Reopening", "Halted"] as const;
