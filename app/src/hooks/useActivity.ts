import { useQuery } from "@tanstack/react-query";
import type { AbiEvent, Client } from "viem";
import { getBlock, getBlockNumber, getLogs } from "viem/actions";
import { clients, D } from "../lib/config";
import { hookAbi, reactiveAbi } from "../lib/abi";
import { tickToPrice } from "../lib/format";

const CHUNK = 9_000n;
type Raw = { tx: string; block: bigint; args: Record<string, unknown> };

/** Incremental log scanner: remembers the last scanned block so each refresh only reads new blocks. */
function scanner(client: Client, address: `0x${string}`, event: AbiEvent, from: bigint) {
  let next = from;
  const seen: Raw[] = [];
  return async (): Promise<Raw[]> => {
    const latest = await getBlockNumber(client);
    while (next <= latest) {
      const to = next + CHUNK - 1n < latest ? next + CHUNK - 1n : latest;
      const logs = await getLogs(client, { address, event, fromBlock: next, toBlock: to });
      for (const l of logs) seen.push({ tx: l.transactionHash!, block: l.blockNumber!, args: (l as { args: Record<string, unknown> }).args });
      next = to + 1n;
    }
    return seen;
  };
}

const ev = (abi: readonly unknown[], name: string) => (abi as AbiEvent[]).find((e) => e.type === "event" && e.name === name)!;

const scanRequests = scanner(clients.lasna, D.reactive, ev(reactiveAbi, "CallbackRequested"), D.fromBlock.lasna);
const scanAnchors = scanner(clients.base, D.hook, ev(hookAbi, "AnchorUpdated"), D.fromBlock.base);
const scanRegimes = scanner(clients.base, D.hook, ev(hookAbi, "RegimeSet"), D.fromBlock.base);

const tsCache = new Map<string, number>();
async function blockTime(client: Client, key: string, block: bigint) {
  const k = `${key}:${block}`;
  if (!tsCache.has(k)) tsCache.set(k, Number((await getBlock(client, { blockNumber: block })).timestamp));
  return tsCache.get(k)!;
}

export type ActivityKind = "anchor" | "regime" | "reconcile";
export type Activity = {
  seq: number;
  kind: ActivityKind;
  regime: number;
  price: number;
  riskBps: number;
  reactTx: string | null;
  reactAt: number | null;
  destTx: string | null;
  destAt: number | null;
};

const KINDS: ActivityKind[] = ["anchor", "regime", "reconcile"];

/** Reactive callback requests (Lasna) matched by seq to their landing tx on Base Sepolia. */
async function readActivity(): Promise<Activity[]> {
  const [requests, anchors, regimes] = await Promise.all([scanRequests(), scanAnchors(), scanRegimes()]);
  const landed = new Map<number, Raw>();
  for (const l of [...anchors, ...regimes]) landed.set(Number(l.args.seq), l);
  const rows = requests
    .map((r) => {
      const seq = Number(r.args.seq);
      const dest = landed.get(seq) ?? null;
      return {
        seq,
        kind: KINDS[Number(r.args.kind)] ?? "anchor",
        regime: Number(r.args.regime),
        price: tickToPrice(Number(r.args.anchorTick)),
        riskBps: Number(r.args.riskBps),
        reactTx: r.tx,
        reactAt: null as number | null,
        destTx: dest?.tx ?? null,
        destAt: null as number | null,
        _rb: r.block,
        _db: dest?.block ?? null,
      };
    })
    .sort((a, b) => b.seq - a.seq)
    .slice(0, 10);
  await Promise.all(
    rows.map(async (row) => {
      row.reactAt = await blockTime(clients.lasna, "lasna", row._rb);
      if (row._db !== null) row.destAt = await blockTime(clients.base, "base", row._db);
    }),
  );
  return rows.map(({ _rb, _db, ...r }) => r);
}

export const useActivity = () =>
  useQuery({ queryKey: ["activity"], queryFn: readActivity, refetchInterval: 15_000, staleTime: 10_000 });
