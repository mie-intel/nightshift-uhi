import { useQuery } from "@tanstack/react-query";
import type { Address } from "viem";
import { multicall } from "viem/actions";
import { clients, D, DEC, poolKey } from "../lib/config";
import { vaultAbi } from "../lib/abi";
import { tickToPrice } from "../lib/format";

export type VaultRow = {
  address: Address;
  name: string;
  curator: Address;
  perfFeeBps: number;
  followClosedBps: number;
  stock: number; // dSTOCK held (human)
  usd: number; // dUSD held (human)
  tvl: number; // in dUSD at pool price
  rangeLow: number | null; // dUSD per dSTOCK
  rangeHigh: number | null;
  alphaPct: number | null; // cumulative alpha vs HODL, % of NAV/share
  epochs: number;
  supply: bigint;
  t0: bigint;
  t1: bigint;
  myShares: bigint;
};

const stockIs0 = poolKey.currency0.toLowerCase() === D.stock.toLowerCase();

async function readVaults(price: number, me?: Address): Promise<VaultRow[]> {
  if (!D.vaults.length) return [];
  const fns = ["name", "curator", "totalSupply", "totals", "liquidity", "lower", "upper", "cumAlpha", "epochsPlayed", "mandate"] as const;
  const calls = D.vaults.flatMap((address) => [
    ...fns.map((functionName) => ({ address, abi: vaultAbi, functionName })),
    { address, abi: vaultAbi, functionName: "balanceOf", args: [me ?? "0x0000000000000000000000000000000000000000"] },
  ]);
  const res = (await multicall(clients.base, { allowFailure: false, contracts: calls as never })) as unknown[];
  const per = fns.length + 1;
  return D.vaults.map((address, i) => {
    const r = res.slice(i * per, (i + 1) * per);
    const [name, curator, supply, totals, liq, lo, hi, cumAlpha, epochs, mandate, mine] = r as [
      string, Address, bigint, readonly [bigint, bigint], bigint, number, number, bigint, bigint,
      { closed: { followBps: number }; perfFeeBps: number }, bigint,
    ];
    const [t0, t1] = totals;
    const stockRaw = stockIs0 ? t0 : t1;
    const usdRaw = stockIs0 ? t1 : t0;
    const stock = Number(stockRaw) / 10 ** DEC.stock;
    const usd = Number(usdRaw) / 10 ** DEC.usd;
    const tvl = stock * price + usd;
    // NAV/share in currency1 raw, wad-scaled — to express cumAlpha (currency1 wad/share) as a %
    const nav1 = stockIs0 ? Number(t0) * (price * 10 ** (DEC.usd - DEC.stock)) + Number(t1) : Number(t1) / (price * 10 ** (DEC.usd - DEC.stock)) + Number(t0);
    const navPerShareWad = supply > 0n ? (nav1 * 1e18) / Number(supply) : 0;
    const a = tickToPrice(lo);
    const b = tickToPrice(hi);
    return {
      address,
      name,
      curator,
      perfFeeBps: mandate.perfFeeBps,
      followClosedBps: mandate.closed.followBps,
      stock,
      usd,
      tvl,
      rangeLow: liq > 0n ? Math.min(a, b) : null,
      rangeHigh: liq > 0n ? Math.max(a, b) : null,
      alphaPct: navPerShareWad > 0 && Number(epochs) > 0 ? (Number(cumAlpha) / navPerShareWad) * 100 : null,
      epochs: Number(epochs),
      supply,
      t0,
      t1,
      myShares: mine,
    };
  });
}

export const useVaults = (price: number | undefined, me?: Address) =>
  useQuery({
    queryKey: ["vaults", me, price ? Math.round(price * 100) : 0],
    enabled: price !== undefined,
    queryFn: () => readVaults(price!, me),
    refetchInterval: 20_000,
  });
