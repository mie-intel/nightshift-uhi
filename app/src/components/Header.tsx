import { useConnect, useConnection, useConnectors, useDisconnect } from "wagmi";
import { short } from "../lib/format";
import { Button } from "./ui";

export function WalletButton() {
  const { address, isConnected } = useConnection();
  const connectors = useConnectors();
  const connect = useConnect();
  const disconnect = useDisconnect();
  const hasWallet = connectors.length > 0;

  return isConnected && address ? (
        <Button variant="ghost" onClick={() => disconnect.mutate()}>
          <span className="h-2 w-2 rounded-full bg-good" aria-hidden />
          {short(address)}
        </Button>
      ) : (
        <Button
          onClick={() => hasWallet && connect.mutate({ connector: connectors[0] })}
          disabled={!hasWallet || connect.isPending}
        >
          {hasWallet ? (connect.isPending ? "Connecting…" : "Connect wallet") : "No wallet found"}
        </Button>
      );
}
