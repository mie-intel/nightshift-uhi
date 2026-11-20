import { useEffect, useState } from "react";
import { closedReason, isOpen, nextTransition } from "../lib/calendar";
import { duration, REGIMES } from "../lib/format";
import { usePool } from "../hooks/usePool";
import { Card, Pill } from "./ui";

function useNow(ms = 30_000) {
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));
  useEffect(() => {
    const id = setInterval(() => setNow(Math.floor(Date.now() / 1000)), ms);
    return () => clearInterval(id);
  }, [ms]);
  return now;
}

export function MarketStatus() {
  const now = useNow();
  const open = isOpen(now);
  const next = nextTransition(now);
  const pool = usePool();

  return (
    <Card className="flex flex-col justify-between gap-5">
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-lg font-semibold">NYSE right now</h2>
        <Pill tone={open ? "good" : "warn"}>
          <span className={`h-2 w-2 rounded-full ${open ? "bg-good" : "bg-warn"} live-dot`} aria-hidden />
          {open ? "Open" : "Closed"}
        </Pill>
      </div>
      <div>
        <p className="text-3xl font-bold tracking-tight">
          {open ? "Market is open" : closedReason(now)}
        </p>
        {next && (
          <p className="mt-1 text-muted">
            {open ? "Closes" : "Opens"} in <span className="font-semibold text-ink tabular-nums">{duration(next - now)}</span>
          </p>
        )}
      </div>
      <p className="border-t border-line pt-4 text-sm text-muted">
        Pool mode:{" "}
        <span className="font-semibold text-ink">{pool.data ? REGIMES[pool.data.regime] ?? "—" : "…"}</span>
        <span className="text-muted"> · set on-chain by NightShift</span>
      </p>
    </Card>
  );
}
