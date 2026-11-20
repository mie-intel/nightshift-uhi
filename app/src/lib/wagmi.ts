import { createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors/injected";
import { baseSepolia, sepolia } from "viem/chains";
import { RPC } from "./config";

/** Browser wallet only (no WalletConnect/RainbowKit) — small bundle, one obvious button. */
export const wagmiConfig = createConfig({
  chains: [baseSepolia, sepolia],
  connectors: [injected()],
  transports: { [baseSepolia.id]: http(RPC.base), [sepolia.id]: http(RPC.eth) },
});

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}
