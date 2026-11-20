import { createClient, defineChain, http, type Address, type Hex } from "viem";
import { baseSepolia, sepolia } from "viem/chains";
import deployments from "../../../deployments/testnet.json";
import params from "../../../contracts/config/testnet.json";

/** Reactive Network testnet (read-only here; the reactive contract lives on it). */
export const lasna = defineChain({
  id: 5318007,
  name: "Reactive Lasna",
  nativeCurrency: { name: "lREACT", symbol: "lREACT", decimals: 18 },
  rpcUrls: { default: { http: ["https://lasna-rpc.rnk.dev/"] } },
  blockExplorers: { default: { name: "Reactscan", url: "https://lasna.reactscan.net" } },
});

const env = import.meta.env;
export const RPC = {
  base: env.VITE_RPC_BASE_SEPOLIA || "https://base-sepolia-rpc.publicnode.com", // sepolia.base.org caps eth_getLogs at 200 blocks
  eth: env.VITE_RPC_ETH_SEPOLIA || "https://ethereum-sepolia-rpc.publicnode.com",
  lasna: env.VITE_RPC_LASNA || "https://lasna-rpc.rnk.dev/",
};

/** Bare clients + tree-shakable actions from "viem/actions" (createPublicClient would bundle every action). */
export const clients = {
  base: createClient({ chain: baseSepolia, transport: http(RPC.base), batch: { multicall: true } }),
  eth: createClient({ chain: sepolia, transport: http(RPC.eth) }),
  lasna: createClient({ chain: lasna, transport: http(RPC.lasna) }),
};

const ZERO = "0x0000000000000000000000000000000000000000";
const dest = deployments.destination;

/** Every address comes from deployments/testnet.json (never hard-coded). */
export const D = {
  issuer: deployments.ethSepolia.mockIssuer as Address,
  originUsd: deployments.ethSepolia.dUsd as Address,
  hook: dest.hook as Address,
  controller: dest.controller as Address,
  poolManager: dest.poolManager as Address,
  poolId: dest.poolId as Hex,
  stock: dest.dStock as Address,
  usd: dest.dUsd as Address,
  swapRouter: dest.swapRouter as Address,
  siblingPoolId: ((dest as { siblingPoolId?: string }).siblingPoolId ?? "0x") as Hex,
  siblingFee: Number((dest as { siblingFee?: number }).siblingFee ?? 3000),
  vaults: (((dest as { vaults?: string[] }).vaults ?? []) as Address[]),
  faucet: ((dest as { faucet?: string }).faucet ?? ZERO) as Address,
  invert: dest.invert as boolean,
  reactive: deployments.lasna.reactive as Address,
  fromBlock: {
    eth: BigInt(deployments.ethSepolia.deployBlock),
    base: BigInt(dest.deployBlock),
    lasna: BigInt(deployments.lasna.deployBlock),
  },
};

export const hasFaucet = D.faucet.toLowerCase() !== ZERO;

export const DEC = { stock: params.demo.stockDecimals, usd: params.demo.usdDecimals };

/** Pool key: currencies sorted by address, dynamic fee flag, spacing from config. */
const [c0, c1] = D.stock.toLowerCase() < D.usd.toLowerCase() ? [D.stock, D.usd] : [D.usd, D.stock];
export const poolKey = {
  currency0: c0,
  currency1: c1,
  fee: 0x800000,
  tickSpacing: params.pool.tickSpacing,
  hooks: D.hook,
} as const;

/** Sibling pool B: same pair, no hook — a separate market Reactive witnesses. */
export const siblingKey = { ...poolKey, fee: D.siblingFee, hooks: "0x0000000000000000000000000000000000000000" as Address } as const;

export const CHAIN_NAMES: Record<number, string> = { 11155111: "Ethereum Sepolia", 84532: "Base Sepolia", 5318007: "Reactive Lasna" };

/** Buying dSTOCK pays dUSD. If dUSD is currency0 (invert), that is zeroForOne. */
export const BUY_ZERO_FOR_ONE = D.invert;

export const FEE = params.fee;

export const explorer = {
  eth: (tx: string) => `https://sepolia.etherscan.io/tx/${tx}`,
  base: (tx: string) => `https://sepolia.basescan.org/tx/${tx}`,
  lasna: (tx: string) => `https://lasna.reactscan.net/tx/${tx}`,
  baseAddr: (a: string) => `https://sepolia.basescan.org/address/${a}`,
  ethAddr: (a: string) => `https://sepolia.etherscan.io/address/${a}`,
  lasnaAddr: (a: string) => `https://lasna.reactscan.net/address/${a}`,
};
