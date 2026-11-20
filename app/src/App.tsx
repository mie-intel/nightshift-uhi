import { lazy, Suspense } from "react";
import { Brand } from "./components/Brand";
import { MarketStatus } from "./components/MarketStatus";
import { FeesCard, PriceCard, RiskCard } from "./components/Overview";
import { HowItWorks } from "./components/HowItWorks";
import { Activity } from "./components/Activity";
import { Witnesses } from "./components/Witnesses";
import { Footer } from "./components/Footer";
import { Card, Skeleton } from "./components/ui";

// wallet code loads after first paint (read-only view needs none of it)
const WalletButton = lazy(() => import("./wallet/lazy").then((m) => ({ default: m.WalletButtonLazy })));
const SwapPanel = lazy(() => import("./wallet/lazy").then((m) => ({ default: m.SwapPanelLazy })));
const OwnerPanel = lazy(() => import("./wallet/lazy").then((m) => ({ default: m.OwnerPanelLazy })));

export default function App() {
  return (
    <>
      <header className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-5 py-5">
        <Brand />
        <Suspense fallback={<Skeleton className="h-11 w-36 rounded-xl" />}>
          <WalletButton />
        </Suspense>
      </header>
      <main className="mx-auto flex max-w-6xl flex-col gap-6 px-5">
        <div className="grid items-stretch gap-6 lg:grid-cols-[3fr_2fr]">
          <div className="flex flex-col justify-center gap-4 py-4">
            <h1 className="text-4xl font-bold leading-tight tracking-tight sm:text-5xl">
              Fair prices for tokenized stocks, even when Wall Street sleeps.
            </h1>
            <p className="max-w-xl text-lg text-muted">
              NightShift brings the price from other chains into this Uniswap v4 pool, so trades that fix the price are
              served and trades that push it away pay for the risk.
            </p>
          </div>
          <MarketStatus />
        </div>

        <div className="grid gap-6 md:grid-cols-3">
          <PriceCard />
          <RiskCard />
          <FeesCard />
        </div>

        <div className="grid gap-6 lg:grid-cols-[3fr_2fr]">
          <Suspense fallback={<Card><Skeleton className="h-80 w-full" /></Card>}>
            <SwapPanel />
          </Suspense>
          <div className="flex flex-col gap-6">
            <Suspense fallback={null}>
              <OwnerPanel />
            </Suspense>
            <HowItWorks />
          </div>
        </div>

        <Witnesses />
        <Activity />
      </main>
      <Footer />
    </>
  );
}
