import { D, explorer, hasFaucet } from "../lib/config";
import { short } from "../lib/format";
import { Ext } from "./ui";

const CONTRACTS = [
  { name: "NightShift hook", chain: "Base Sepolia", addr: D.hook, url: explorer.baseAddr },
  { name: "Controller", chain: "Base Sepolia", addr: D.controller, url: explorer.baseAddr },
  { name: "Reactive contract", chain: "Reactive Lasna", addr: D.reactive, url: explorer.lasnaAddr },
  { name: "Issuer (mock)", chain: "Ethereum Sepolia", addr: D.issuer, url: explorer.ethAddr },
  ...(hasFaucet ? [{ name: "Demo faucet", chain: "Base Sepolia", addr: D.faucet, url: explorer.baseAddr }] : []),
];

export function Footer() {
  return (
    <footer className="mx-auto mt-4 max-w-6xl px-5 pb-12">
      <div className="grid gap-6 border-t border-line pt-8 md:grid-cols-[2fr_3fr]">
        <div className="space-y-2 text-sm text-muted">
          <p className="font-semibold text-ink">Testnet demo</p>
          <p>Demo tokens only — not real securities. Trades in this pool are demo flow; the fair price comes from real on-chain events on other chains, delivered by Reactive Network.</p>
          <p>Uniswap v4 hook · Reactive Network · UHI11 Hookathon. Credits: Gapguard (closed-market fee ideas), Maestro, horsefacts/trading-days.</p>
        </div>
        <ul className="grid gap-2 text-sm sm:grid-cols-2">
          {CONTRACTS.map((c) => (
            <li key={c.name} className="rounded-xl bg-surface px-3 py-2">
              <span className="block font-semibold">{c.name}</span>
              <span className="text-muted">{c.chain} · </span>
              <Ext href={c.url(c.addr)}>{short(c.addr)}</Ext>
            </li>
          ))}
        </ul>
      </div>
    </footer>
  );
}
