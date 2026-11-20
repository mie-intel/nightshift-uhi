import type { ReactNode } from "react";
import { WagmiProvider } from "wagmi";
import { wagmiConfig } from "../lib/wagmi";

/** Wallet code (wagmi + connectors) is lazy-loaded: the read-only dashboard paints without it.
 *  Several scopes share one config, so they share one wallet state. Only the header scope reconnects on mount. */
export function WalletScope({ children, reconnect = false }: { children: ReactNode; reconnect?: boolean }) {
  return (
    <WagmiProvider config={wagmiConfig} reconnectOnMount={reconnect}>
      {children}
    </WagmiProvider>
  );
}
