import { usePool, type QuotedFee } from "../hooks/usePool";
import { ago, pct, signedPct, usd } from "../lib/format";
import { Card, Pill, Skeleton } from "./ui";

/** Horizontal meter: fair price in the middle, pool price marker offset by the gap (±5% full scale). */
function GapMeter({ gap }: { gap: number }) {
  const span = 0.05;
  const x = 150 + Math.max(-1, Math.min(1, gap / span)) * 138;
  return (
    <svg viewBox="0 0 300 28" className="h-7 w-full" role="img" aria-label={`Pool is ${signedPct(gap)} from fair price`}>
      <rect x="12" y="12" width="276" height="4" rx="2" fill="var(--color-tint)" />
      <line x1="150" y1="4" x2="150" y2="24" stroke="var(--color-good)" strokeWidth="2.5" strokeLinecap="round" />
      <line x1="150" y1="14" x2={x} y2="14" stroke="var(--color-accent)" strokeWidth="4" strokeLinecap="round" />
      <circle cx={x} cy="14" r="7" fill="var(--color-accent)" stroke="var(--color-surface)" strokeWidth="2.5" />
    </svg>
  );
}

export function PriceCard() {
  const { data, isLoading } = usePool();
  const gap = data?.anchorPrice ? data.poolPrice / data.anchorPrice - 1 : null;

  return (
    <Card className="flex flex-col gap-4">
      <h2 className="text-lg font-semibold">Price of dSTOCK</h2>
      <div className="grid grid-cols-2 gap-4">
        <div>
          <p className="text-sm text-muted">In this pool</p>
          <p className="text-2xl font-bold tabular-nums">{isLoading ? <Skeleton className="h-7 w-24" /> : `$${usd(data!.poolPrice)}`}</p>
        </div>
        <div>
          <p className="text-sm text-muted">Fair price</p>
          <p className="text-2xl font-bold tabular-nums text-good">
            {isLoading ? <Skeleton className="h-7 w-24" /> : data?.anchorPrice ? `$${usd(data.anchorPrice)}` : "—"}
          </p>
        </div>
      </div>
      {gap !== null ? (
        <div>
          <GapMeter gap={gap} />
          <p className="text-sm text-muted">
            Pool is <span className="font-semibold text-ink tabular-nums">{signedPct(gap)}</span> vs the fair price
            witnessed on other chains.
          </p>
        </div>
      ) : (
        !isLoading && <p className="text-sm text-muted">No fair price received yet.</p>
      )}
    </Card>
  );
}

export function RiskCard() {
  const { data, isLoading } = usePool();
  const risk = data ? data.riskBps / 100 : 0;
  const now = Date.now() / 1000;

  return (
    <Card className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold">Gap risk</h2>
        {data && (data.stale ? <Pill tone="bad">Max protection</Pill> : <Pill tone="good">Fresh price</Pill>)}
      </div>
      <p className="text-2xl font-bold tabular-nums">{isLoading ? <Skeleton className="h-7 w-16" /> : `${risk.toFixed(0)}%`}</p>
      <div className="h-2.5 w-full overflow-hidden rounded-full bg-tint" role="meter" aria-valuemin={0} aria-valuemax={100} aria-valuenow={risk} aria-label="Gap risk">
        <div className="h-full rounded-full bg-accent transition-[width]" style={{ width: `${Math.max(2, risk)}%` }} />
      </div>
      <p className="text-sm text-muted">
        {data?.anchorUpdatedAt
          ? <>Fair price updated <span className="font-semibold text-ink">{ago(now - data.anchorUpdatedAt)}</span> by a Reactive callback.</>
          : "Waiting for the first fair price."}
        {data?.stale && " It is too old, so every trade is treated as risky."}
      </p>
    </Card>
  );
}

function FeeRow({ label, q }: { label: string; q: QuotedFee }) {
  return (
    <div className="flex items-center justify-between gap-3 py-2">
      <div>
        <p className="font-semibold">{label}</p>
        {q && <p className="text-sm text-muted">{q.away ? "Moves away from fair price" : "Moves toward fair price"}</p>}
      </div>
      <div className="text-right">
        <p className="text-xl font-bold tabular-nums">{q ? pct(q.fee) : "—"}</p>
        {q && (q.away ? <Pill tone="bad">Pricier</Pill> : <Pill tone="good">Repair</Pill>)}
      </div>
    </div>
  );
}

export function FeesCard() {
  const { data, isLoading } = usePool();
  return (
    <Card className="flex flex-col gap-2">
      <h2 className="text-lg font-semibold">Trading fee now</h2>
      {isLoading ? (
        <Skeleton className="h-24 w-full" />
      ) : (
        <div className="divide-y divide-line">
          <FeeRow label="Buy dSTOCK" q={data?.buy ?? null} />
          <FeeRow label="Sell dSTOCK" q={data?.sell ?? null} />
        </div>
      )}
    </Card>
  );
}
