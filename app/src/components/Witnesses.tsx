import { useWitnesses } from "../hooks/useWitnesses";
import { CHAIN_NAMES, explorer, D } from "../lib/config";
import { ago, usd } from "../lib/format";
import { Card, Ext, Pill, Skeleton } from "./ui";

const KIND_LABEL: Record<number, string> = {
  0: "Issuer mints",
  1: "Issuer redeems",
  2: "Sibling Uniswap pool",
  3: "Uniswap v3 pool",
  4: "Oracle",
  5: "This pool",
};

export function Witnesses() {
  const { data, isLoading, isError } = useWitnesses();
  const now = Date.now() / 1000;
  const chains = new Set(
    data?.witnesses.filter((w) => !w.self && w.lastSeen > 0 && now - w.lastSeen <= w.maxAge).map((w) => w.chainId),
  );

  return (
    <Card className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h2 className="text-xl font-semibold">Where the fair price comes from</h2>
          <p className="mt-1 text-muted">
            A Reactive contract watches these markets on other chains. It needs fresh prices from at least 2 chains
            before it moves the pool.
          </p>
        </div>
        {data && (data.quorum ? <Pill tone="good">Quorum reached · {chains.size} chains</Pill> : <Pill tone="warn">Waiting for quorum</Pill>)}
      </div>
      {isLoading && <Skeleton className="h-32 w-full" />}
      {isError && <p className="text-bad">Could not reach Reactive Network. Retrying…</p>}
      {data && (
        <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead className="text-sm text-muted">
              <tr className="border-b border-line">
                <th className="py-2 pr-4 font-medium">Source</th>
                <th className="py-2 pr-4 font-medium">Chain</th>
                <th className="py-2 pr-4 font-medium">Weight</th>
                <th className="py-2 pr-4 font-medium">Price seen</th>
                <th className="py-2 font-medium">Last update</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-line">
              {data.witnesses.map((w) => {
                const fresh = w.lastSeen > 0 && now - w.lastSeen <= w.maxAge;
                return (
                  <tr key={w.index}>
                    <td className="py-3 pr-4 font-semibold">{KIND_LABEL[w.kind] ?? "Source"}</td>
                    <td className="py-3 pr-4 text-muted">{CHAIN_NAMES[w.chainId] ?? w.chainId}</td>
                    <td className="py-3 pr-4 tabular-nums">{w.self ? "risk only" : w.weight}</td>
                    <td className="py-3 pr-4 tabular-nums">{w.price !== null ? `$${usd(w.price)}` : "—"}</td>
                    <td className="py-3">
                      {w.lastSeen === 0 ? (
                        <span className="text-muted">not yet</span>
                      ) : (
                        <span className="flex items-center gap-2">
                          <span className="tabular-nums">{ago(now - w.lastSeen)}</span>
                          {!w.self && (fresh ? <Pill tone="good">Fresh</Pill> : <Pill tone="neutral">Stale</Pill>)}
                        </span>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
      <p className="text-sm text-muted">
        Reactive contract: <Ext href={explorer.lasnaAddr(D.reactive)}>view on Reactscan</Ext>
      </p>
    </Card>
  );
}
