import { useActivity, type Activity as Row } from "../hooks/useActivity";
import { explorer } from "../lib/config";
import { usd } from "../lib/format";
import { Card, Pill, Skeleton } from "./ui";

const REGIME_TEXT = ["Market open", "Market closed", "Market reopening", "Halted"];

function title(r: Row): { text: string; tone: "good" | "warn" | "neutral" } {
  if (r.kind === "regime") return { text: REGIME_TEXT[r.regime] ?? "Regime change", tone: r.regime === 1 ? "warn" : "neutral" };
  if (r.kind === "reconcile") return { text: "Reopen reconciled", tone: "good" };
  return { text: `Fair price $${usd(r.price)}`, tone: "good" };
}

function Hop({ label, href, done }: { label: string; href: string | null; done: boolean }) {
  const dot = (
    <span className={`flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs font-bold ${done ? "bg-good text-white" : "bg-tint text-muted"}`} aria-hidden>
      {done ? "✓" : "…"}
    </span>
  );
  return href ? (
    <a href={href} target="_blank" rel="noreferrer" className="flex items-center gap-2 rounded-lg px-2 py-1 hover:bg-tint" title="Open in explorer">
      {dot}
      <span className="text-sm font-medium underline decoration-accent/30 underline-offset-4">{label}</span>
    </a>
  ) : (
    <span className="flex items-center gap-2 px-2 py-1 text-sm text-muted">
      {dot}
      {label}
    </span>
  );
}

export function Activity() {
  const { data, isLoading, isError } = useActivity();
  return (
    <Card className="flex flex-col gap-4">
      <div>
        <h2 className="text-xl font-semibold">Updates pushed into the pool</h2>
        <p className="mt-1 text-muted">
          Each row is computed on Reactive Network and delivered to this pool on Base — between trades, no bot, no signer.
        </p>
      </div>
      {isLoading && <Skeleton className="h-28 w-full" />}
      {isError && <p className="text-bad">Could not load updates from the RPCs. Retrying…</p>}
      {data && data.length === 0 && <p className="text-muted">No updates yet.</p>}
      {data && data.length > 0 && (
        <ol className="divide-y divide-line">
          {data.map((r) => {
            const t = title(r);
            const secs = r.reactAt && r.destAt ? r.destAt - r.reactAt : null;
            return (
              <li key={r.seq} className="flex flex-wrap items-center justify-between gap-3 py-3">
                <div className="flex min-w-0 items-center gap-3">
                  <span className="w-10 shrink-0 text-sm text-muted tabular-nums">#{r.seq}</span>
                  <Pill tone={t.tone}>{t.text}</Pill>
                  {r.kind === "anchor" && <span className="text-sm text-muted tabular-nums">risk {(r.riskBps / 100).toFixed(0)}%</span>}
                </div>
                <div className="flex flex-wrap items-center gap-1">
                  <Hop label="Reactive Network" href={r.reactTx && explorer.lasna(r.reactTx)} done={!!r.reactTx} />
                  <span className="text-muted" aria-hidden>→</span>
                  <Hop label="Base Sepolia" href={r.destTx && explorer.base(r.destTx)} done={!!r.destTx} />
                  <span className="w-28 text-right text-sm text-muted tabular-nums">
                    {secs !== null ? `${secs}s` : r.destTx ? "" : "delivering…"}
                    {r.destAt ? ` · ${new Date(r.destAt * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}` : ""}
                  </span>
                </div>
              </li>
            );
          })}
        </ol>
      )}
    </Card>
  );
}
