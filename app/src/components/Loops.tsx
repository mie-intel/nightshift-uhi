import { useLoops, type Loop } from "../hooks/useLoops";
import { explorer } from "../lib/config";
import { usd } from "../lib/format";
import { Card, Skeleton } from "./ui";

function Step({ n, chain, text, href }: { n: number; chain: string; text: string; href: string | null }) {
  const body = (
    <>
      <span className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-sm font-bold ${href ? "bg-good text-white" : "bg-tint text-muted"}`} aria-hidden>
        {href ? "✓" : n}
      </span>
      <span className="min-w-0">
        <span className="block font-semibold">{chain}</span>
        <span className="block text-sm text-muted">{text}</span>
      </span>
    </>
  );
  return href ? (
    <a href={href} target="_blank" rel="noreferrer" className="flex flex-1 items-start gap-3 rounded-xl p-3 hover:bg-tint" title="Open in explorer">
      {body}
    </a>
  ) : (
    <div className="flex flex-1 items-start gap-3 rounded-xl p-3 opacity-70">{body}</div>
  );
}

function Arrow() {
  return <span className="hidden self-center text-muted md:block" aria-hidden>→</span>;
}

function LoopRow({ loop }: { loop: Loop }) {
  const secs = loop.mintAt && loop.anchorAt ? loop.anchorAt - loop.mintAt : null;
  return (
    <li className="rounded-2xl border border-line p-2">
      <div className="flex flex-wrap items-center justify-between gap-2 px-3 pt-2">
        <p className="font-semibold">Update #{loop.seq}</p>
        <p className="text-sm text-muted">
          {secs !== null && <>Done in <span className="font-semibold text-ink tabular-nums">{secs}s</span> · </>}
          {loop.anchorAt && new Date(loop.anchorAt * 1000).toLocaleString()}
        </p>
      </div>
      <div className="flex flex-col gap-1 md:flex-row">
        <Step n={1} chain="Ethereum Sepolia" text={loop.issuerPrice ? `Issuer sold at $${usd(loop.issuerPrice)}` : "Issuer trade"} href={loop.mintTx && explorer.eth(loop.mintTx)} />
        <Arrow />
        <Step n={2} chain="Reactive Network" text="Computed fair price, sent callback" href={loop.reactTx && explorer.lasna(loop.reactTx)} />
        <Arrow />
        <Step n={3} chain="Base Sepolia" text={`Pool fair price set to $${usd(loop.anchorPrice)}`} href={loop.anchorTx && explorer.base(loop.anchorTx)} />
      </div>
    </li>
  );
}

export function Loops() {
  const { data, isLoading, isError } = useLoops();
  return (
    <Card className="flex flex-col gap-4">
      <div>
        <h2 className="text-xl font-semibold">Fair-price updates from other chains</h2>
        <p className="mt-1 text-muted">Each update is real on-chain proof: a trade on one chain changes this pool on another, with no trade on the pool itself.</p>
      </div>
      {isLoading && <Skeleton className="h-28 w-full" />}
      {isError && <p className="text-bad">Could not load updates from the RPCs. Retrying…</p>}
      {data && data.length === 0 && <p className="text-muted">No updates yet.</p>}
      {data && data.length > 0 && (
        <ol className="flex flex-col gap-3">
          {data.slice(0, 8).map((l) => (
            <LoopRow key={l.seq} loop={l} />
          ))}
        </ol>
      )}
    </Card>
  );
}
