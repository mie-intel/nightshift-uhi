import { useQuery } from "@tanstack/react-query";
import { readContract } from "viem/actions";
import { clients, D } from "../lib/config";
import { reactiveAbi } from "../lib/abi";
import { tickToPrice } from "../lib/format";

export type Witness = {
  index: number;
  kind: number;
  chainId: number;
  weight: number;
  price: number | null;
  lastSeen: number;
  maxAge: number;
  self: boolean;
};

export type WitnessView = { quorum: boolean; regime: number; riskBps: number; witnesses: Witness[] };

const r = <T,>(functionName: string, args: unknown[] = []) =>
  readContract(clients.lasna, { address: D.reactive, abi: reactiveAbi, functionName, args } as never) as Promise<T>;

/** Reads witness sources and quorum state straight from the reactive contract on Lasna. */
async function readWitnesses(): Promise<WitnessView> {
  const [n, quorum, regime, riskBps] = await Promise.all([
    r<bigint>("sourceCount"),
    r<boolean>("quorum"),
    r<number>("regime"),
    r<number>("riskBps"),
  ]);
  const rows = await Promise.all(
    Array.from({ length: Number(n) }, (_, i) =>
      r<[{ chainId: bigint; kind: number; weight: number; maxAgeOpen: number; maxAgeClosed: number; enabled: boolean }, { ewma: number; lastRaw: number; lastSeen: number }]>("sourceAt", [BigInt(i)]),
    ),
  );
  const witnesses = rows
    .map(([s, st], index) => ({
      index,
      kind: s.kind,
      chainId: Number(s.chainId),
      weight: s.weight,
      self: s.kind === 5,
      lastSeen: Number(st.lastSeen),
      maxAge: regime === 0 ? s.maxAgeOpen : s.maxAgeClosed,
      // SELF stores no EWMA (divergence only); other sources show their smoothed price
      price: Number(st.lastSeen) > 0 && s.kind !== 5 ? tickToPrice(st.ewma) : null,
      enabled: s.enabled,
    }))
    .filter((w) => w.enabled);
  return { quorum, regime, riskBps, witnesses };
}

export const useWitnesses = () =>
  useQuery({ queryKey: ["witnesses"], queryFn: readWitnesses, refetchInterval: 20_000, staleTime: 10_000 });
