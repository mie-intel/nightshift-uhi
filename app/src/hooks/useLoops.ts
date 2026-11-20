import { useQuery } from "@tanstack/react-query";
import type { AbiEvent, Client } from "viem";
import { getBlock, getBlockNumber, getLogs } from "viem/actions";
import { clients, D, DEC } from "../lib/config";
import { hookAbi, issuerAbi, reactiveAbi } from "../lib/abi";
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

const ev = (abi: readonly unknown[], name: string) =>
  (abi as AbiEvent[]).find((e) => e.type === "event" && e.name === name)!;

const scanMints = scanner(clients.eth, D.issuer, ev(issuerAbi, "Minted"), D.fromBlock.eth);
const scanRequests = scanner(clients.lasna, D.reactive, ev(reactiveAbi, "CallbackRequested"), D.fromBlock.lasna);
const scanAnchors = scanner(clients.base, D.hook, ev(hookAbi, "AnchorUpdated"), D.fromBlock.base);

const tsCache = new Map<string, number>();
async function blockTime(client: Client, key: string, block: bigint) {
  const k = `${key}:${block}`;
  if (!tsCache.has(k)) tsCache.set(k, Number((await getBlock(client, { blockNumber: block })).timestamp));
  return tsCache.get(k)!;
}

export type Loop = {
  seq: number;
  issuerPrice: number | null;
  mintTx: string | null;
  mintAt: number | null;
  reactTx: string | null;
  anchorTx: string | null;
  anchorAt: number | null;
  anchorPrice: number;
};

async function readLoops(): Promise<Loop[]> {
  const [mints, requests, anchors] = await Promise.all([scanMints(), scanRequests(), scanAnchors()]);
  const bySeq = new Map<number, Loop>();
  const get = (seq: number, tick: number) => {
    if (!bySeq.has(seq))
      bySeq.set(seq, { seq, issuerPrice: null, mintTx: null, mintAt: null, reactTx: null, anchorTx: null, anchorAt: null, anchorPrice: tickToPrice(tick) });
    return bySeq.get(seq)!;
  };
  for (const r of requests) get(Number(r.args.seq), Number(r.args.anchorTick)).reactTx = r.tx;
  for (const a of anchors) {
    const loop = get(Number(a.args.seq), Number(a.args.anchorTick));
    loop.anchorTx = a.tx;
    loop.anchorAt = await blockTime(clients.base, "base", a.block);
  }
  // v0 has one witness: the k-th issuer mint produced seq k.
  const loops = [...bySeq.values()].sort((a, b) => b.seq - a.seq);
  for (const loop of loops) {
    const m = mints[loop.seq - 1];
    if (!m) continue;
    loop.mintTx = m.tx;
    loop.mintAt = await blockTime(clients.eth, "eth", m.block);
    const shares = Number(m.args.shares as bigint) / 10 ** DEC.stock;
    const quote = Number(m.args.quoteAmount as bigint) / 10 ** DEC.usd;
    loop.issuerPrice = shares > 0 ? quote / shares : null;
  }
  return loops;
}

export const useLoops = () =>
  useQuery({ queryKey: ["loops"], queryFn: readLoops, refetchInterval: 15_000, staleTime: 10_000 });
