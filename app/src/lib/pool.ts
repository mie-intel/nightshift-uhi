import { encodeAbiParameters, keccak256, type Hex } from "viem";
import { readContract } from "viem/actions";
import { clients, D } from "./config";
import { poolManagerAbi } from "./abi";

/** v4 PoolManager stores Pool.State at keccak256(poolId, POOLS_SLOT = 6); slot0 = first word. */
export const slot0Key = (poolId: Hex) =>
  keccak256(encodeAbiParameters([{ type: "bytes32" }, { type: "uint256" }], [poolId, 6n]));

/** Decode the signed 24-bit tick from a slot0 word. */
export function tickFromSlot0(word: Hex | bigint): number {
  const raw = Number((BigInt(word) >> 160n) & 0xffffffn);
  return raw >= 0x800000 ? raw - 0x1000000 : raw;
}

export async function readPoolTick(poolId: Hex): Promise<number> {
  const word = await readContract(clients.base, { address: D.poolManager, abi: poolManagerAbi, functionName: "extsload", args: [slot0Key(poolId)] });
  return tickFromSlot0(word);
}

/** sqrt(1.0001^tick)·2^96 — float precision is plenty for a swap price limit. */
export function sqrtAtTick(tick: number): bigint {
  const s = Math.sqrt(Math.pow(1.0001, tick));
  return BigInt(Math.floor(s * 2 ** 48)) * 2n ** 48n;
}
