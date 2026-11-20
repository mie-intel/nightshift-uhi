import { WalletScope } from "./WalletScope";
import { WalletButton } from "../components/Header";
import { SwapPanel } from "../components/SwapPanel";
import { OwnerPanel } from "../components/OwnerPanel";
import { Vaults } from "../components/Vaults";

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
export const VaultsLazy = () => (
  <WalletScope>
    <Vaults />
  </WalletScope>
);
export const OwnerPanelLazy = () => (
  <WalletScope>
    <OwnerPanel />
  </WalletScope>
);
