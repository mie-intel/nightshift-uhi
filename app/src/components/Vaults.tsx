import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useConnection, useSwitchChain, useWriteContract } from "wagmi";
import { baseSepolia } from "viem/chains";
import { maxUint256, parseUnits } from "viem";
import { readContract, waitForTransactionReceipt } from "viem/actions";
import { clients, D, DEC, explorer, poolKey } from "../lib/config";
import { erc20Abi, vaultAbi } from "../lib/abi";
import { friendlyError } from "../lib/errors";
import { short, usd } from "../lib/format";
import { usePool } from "../hooks/usePool";
import { useVaults, type VaultRow } from "../hooks/useVaults";
import { Button, Card, Ext, Pill, Skeleton } from "./ui";

const STYLE = (follow: number) => (follow >= 10_000 ? "Follows fair price fully" : `Follows ${follow / 100}% of the gap`);

function VaultCard({ v, rank }: { v: VaultRow; rank: number }) {
  const { address, chainId, isConnected } = useConnection();
  const switchChain = useSwitchChain();
  const write = useWriteContract();
  const qc = useQueryClient();
  const [amount, setAmount] = useState("500");
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ ok: boolean; text: string; tx?: string } | null>(null);
  const stockIs0 = poolKey.currency0.toLowerCase() === D.stock.toLowerCase();

  const run = async (fn: () => Promise<`0x${string}` | undefined>, done: string) => {
    setMsg(null);
    try {
      if (chainId !== baseSepolia.id) await switchChain.mutateAsync({ chainId: baseSepolia.id });
      const tx = await fn();
      setMsg({ ok: true, text: done, tx });
      await qc.invalidateQueries();
    } catch (e) {
      setMsg({ ok: false, text: friendlyError(e) });
    } finally {
      setBusy(null);
    }
  };

  // in-kind deposit: user picks a dUSD amount, the matching dSTOCK follows the vault's current composition
  const deposit = () =>
    run(async () => {
      const usdRaw = parseUnits(amount || "0", DEC.usd);
      const [tUsd, tStock] = stockIs0 ? [v.t1, v.t0] : [v.t0, v.t1];
      const stockRaw = tUsd > 0n ? (usdRaw * tStock) / tUsd + 1n : 0n;
      for (const [token, need] of [[D.usd, usdRaw], [D.stock, stockRaw]] as const) {
        const allowance = await readContract(clients.base, { address: token, abi: erc20Abi, functionName: "allowance", args: [address!, v.address] });
        if (allowance < need) {
          setBusy("Allowing tokens…");
          const h = await write.mutateAsync({ chainId: baseSepolia.id, address: token, abi: erc20Abi, functionName: "approve", args: [v.address, maxUint256] });
          await waitForTransactionReceipt(clients.base, { hash: h });
        }
      }
      setBusy("Depositing…");
      const [a0, a1] = stockIs0 ? [stockRaw, usdRaw] : [usdRaw, stockRaw];
      const h = await write.mutateAsync({ chainId: baseSepolia.id, address: v.address, abi: vaultAbi, functionName: "deposit", args: [a0, a1, 0n, address!] });
      await waitForTransactionReceipt(clients.base, { hash: h });
      return h;
    }, `Deposited into ${v.name}.`);

  const withdraw = () =>
    run(async () => {
      setBusy("Withdrawing…");
      const h = await write.mutateAsync({ chainId: baseSepolia.id, address: v.address, abi: vaultAbi, functionName: "withdraw", args: [v.myShares, 0n, 0n, address!] });
      await waitForTransactionReceipt(clients.base, { hash: h });
      return h;
    }, `Withdrawn from ${v.name}.`);

  const mySharePct = v.supply > 0n ? Number((v.myShares * 10_000n) / v.supply) / 100 : 0;

  return (
    <div className="flex flex-col gap-4 rounded-2xl border border-line p-5">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-sm text-muted">#{rank}</p>
          <h3 className="text-lg font-semibold">{v.name}</h3>
          <p className="text-sm text-muted">
            {STYLE(v.followClosedBps)} · curator <Ext href={explorer.baseAddr(v.curator)}>{short(v.curator)}</Ext>
          </p>
        </div>
        {v.alphaPct === null ? <Pill tone="neutral">No epoch yet</Pill> : <Pill tone={v.alphaPct >= 0 ? "good" : "bad"}>{v.alphaPct >= 0 ? "+" : ""}{v.alphaPct.toFixed(2)}% vs HODL</Pill>}
      </div>
      <dl className="grid grid-cols-3 gap-3 text-sm">
        <div><dt className="text-muted">Value</dt><dd className="font-semibold tabular-nums">${usd(v.tvl, 0)}</dd></div>
        <div><dt className="text-muted">Liquidity range</dt><dd className="font-semibold tabular-nums">{v.rangeLow ? `$${usd(v.rangeLow, 0)}–${usd(v.rangeHigh!, 0)}` : "Parked"}</dd></div>
        <div><dt className="text-muted">Perf fee · epochs</dt><dd className="font-semibold tabular-nums">{v.perfFeeBps / 100}% · {v.epochs}</dd></div>
      </dl>
      {isConnected && (
        <div className="flex flex-wrap items-center gap-2 border-t border-line pt-4">
          <div className="flex items-center rounded-xl border border-field bg-surface px-3">
            <input inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))} className="w-24 bg-transparent py-2 font-semibold tabular-nums outline-none" aria-label="dUSD amount to deposit" />
            <span className="text-sm text-muted">dUSD + dSTOCK</span>
          </div>
          <Button onClick={deposit} disabled={!!busy || !amount}>{busy ?? "Deposit"}</Button>
          {v.myShares > 0n && <Button variant="ghost" onClick={withdraw} disabled={!!busy}>Withdraw all ({mySharePct.toFixed(1)}%)</Button>}
        </div>
      )}
      {msg && (
        <p role="status" className={`rounded-xl px-3 py-2 text-sm ${msg.ok ? "bg-good-soft text-good" : "bg-bad-soft text-bad"}`}>
          {msg.text} {msg.tx && <Ext href={explorer.base(msg.tx)}>View transaction</Ext>}
        </p>
      )}
    </div>
  );
}

export function Vaults() {
  const pool = usePool();
  const { address } = useConnection();
  const { data, isLoading } = useVaults(pool.data?.poolPrice, address);
  const ranked = [...(data ?? [])].sort((a, b) => (b.alphaPct ?? -1e9) - (a.alphaPct ?? -1e9) || b.tvl - a.tvl);

  return (
    <Card className="flex flex-col gap-4">
      <div>
        <h2 className="text-xl font-semibold">Curator vaults</h2>
        <p className="mt-1 text-muted">
          Pick a curator. Their vault moves your liquidity onto the fair price when Reactive updates it — no trade
          needed — and is scored against simply holding at every market reopen. Curators earn a fee only on new gains.
        </p>
      </div>
      {isLoading && <Skeleton className="h-40 w-full" />}
      {data && data.length === 0 && <p className="text-muted">No vaults deployed yet.</p>}
      {data && data.length > 0 && (
        <div className="grid gap-4 lg:grid-cols-3">
          {ranked.map((v, i) => (
            <VaultCard key={v.address} v={v} rank={i + 1} />
          ))}
        </div>
      )}
    </Card>
  );
}
