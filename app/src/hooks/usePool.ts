import { useQuery } from "@tanstack/react-query";
import { encodeAbiParameters, keccak256 } from "viem";
import { multicall } from "viem/actions";
import { clients, D, FEE, poolKey, BUY_ZERO_FOR_ONE } from "../lib/config";
import { hookAbi, poolManagerAbi } from "../lib/abi";
import { tickToPrice } from "../lib/format";

/** v4 PoolManager stores Pool.State at keccak256(poolId, POOLS_SLOT = 6); slot0 = first word. */
const SLOT0 = keccak256(encodeAbiParameters([{ type: "bytes32" }, { type: "uint256" }], [D.poolId, 6n]));

export type QuotedFee = { fee: number; away: boolean } | null;

export type PoolView = {
  tick: number;
  poolPrice: number;
  anchorTick: number | null;
  anchorPrice: number | null;
  anchorUpdatedAt: number;
  riskBps: number;
  regime: number;
  lastSeq: number;
  stale: boolean;
  buy: QuotedFee;
  sell: QuotedFee;
};

async function readPool(): Promise<PoolView> {
  const [slot0, state, buy, sell] = await multicall(clients.base, {
    allowFailure: true,
    contracts: [
      { address: D.poolManager, abi: poolManagerAbi, functionName: "extsload", args: [SLOT0] },
      { address: D.hook, abi: hookAbi, functionName: "poolState", args: [D.poolId] },
      { address: D.hook, abi: hookAbi, functionName: "quoteFee", args: [poolKey, BUY_ZERO_FOR_ONE] },
      { address: D.hook, abi: hookAbi, functionName: "quoteFee", args: [poolKey, !BUY_ZERO_FOR_ONE] },
    ],
  });
  if (slot0.status !== "success" || state.status !== "success") throw new Error("pool read failed");

  const word = BigInt(slot0.result);
  const rawTick = Number((word >> 160n) & 0xffffffn);
  const tick = rawTick >= 0x800000 ? rawTick - 0x1000000 : rawTick;
  const [anchorTick, updatedAt, riskBps, , regime, lastSeq] = state.result;
  const hasAnchor = updatedAt > 0;
  const maxAge = regime === 0 ? FEE.anchorMaxAgeOpen : FEE.anchorMaxAgeClosed;
  const now = Date.now() / 1000;
  const q = (r: typeof buy): QuotedFee =>
    r.status === "success" ? { fee: Number(r.result[0]), away: r.result[1] } : null;

  return {
    tick,
    poolPrice: tickToPrice(tick),
    anchorTick: hasAnchor ? anchorTick : null,
    anchorPrice: hasAnchor ? tickToPrice(anchorTick) : null,
    anchorUpdatedAt: updatedAt,
    riskBps,
    regime,
    lastSeq: Number(lastSeq),
    stale: !hasAnchor || now - updatedAt > maxAge,
    buy: q(buy),
    sell: q(sell),
  };
}

export const usePool = () =>
  useQuery({ queryKey: ["pool"], queryFn: readPool, refetchInterval: 10_000, staleTime: 5_000 });
