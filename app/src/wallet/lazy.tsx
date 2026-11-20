import { WalletScope } from "./WalletScope";
import { WalletButton } from "../components/Header";
import { SwapPanel } from "../components/SwapPanel";
import { OwnerPanel } from "../components/OwnerPanel";

export const WalletButtonLazy = () => (
  <WalletScope reconnect>
    <WalletButton />
  </WalletScope>
);
export const SwapPanelLazy = () => (
  <WalletScope>
    <SwapPanel />
  </WalletScope>
);
export const OwnerPanelLazy = () => (
  <WalletScope>
    <OwnerPanel />
  </WalletScope>
);
