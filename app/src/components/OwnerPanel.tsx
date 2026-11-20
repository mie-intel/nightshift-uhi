import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useConnection, useSwitchChain, useWriteContract } from "wagmi";
import { baseSepolia, sepolia } from "viem/chains";
import { readContract, waitForTransactionReceipt } from "viem/actions";
import { clients, D, DEC, explorer, siblingKey } from "../lib/config";
import { issuerAbi, swapRouterAbi } from "../lib/abi";
import { friendlyError } from "../lib/errors";
import { usd } from "../lib/format";
import { readPoolTick, sqrtAtTick } from "../lib/pool";
import { Button, Card, Ext } from "./ui";

/** Demo control: only the MockIssuer owner sees this. Moves the issuer price and mints 1 share on Ethereum Sepolia. */
export function OwnerPanel() {
  const { address, chainId } = useConnection();
  const switchChain = useSwitchChain();
  const write = useWriteContract();
  const qc = useQueryClient();
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ ok: boolean; text: string; tx?: string } | null>(null);

  const issuer = useQuery({
    queryKey: ["issuer"],
    refetchInterval: 30_000,
    queryFn: async () => {
      const [owner, price] = await Promise.all([
        readContract(clients.eth, { address: D.issuer, abi: issuerAbi, functionName: "owner" }),
        readContract(clients.eth, { address: D.issuer, abi: issuerAbi, functionName: "price" }),
      ]);
      return { owner, price };
    },
  });

  if (!address || !issuer.data || issuer.data.owner.toLowerCase() !== address.toLowerCase()) return null;
  const current = Number(issuer.data.price) / 10 ** DEC.usd;

  const move = async (bps: number) => {
    setMsg(null);
    try {
      if (chainId !== sepolia.id) {
        setBusy("Switching to Ethereum Sepolia…");
        await switchChain.mutateAsync({ chainId: sepolia.id });
      }
      const next = (issuer.data!.price * BigInt(10_000 + bps)) / 10_000n;
      setBusy("1/2 Setting issuer price…");
      const h1 = await write.mutateAsync({ chainId: sepolia.id, address: D.issuer, abi: issuerAbi, functionName: "setPrice", args: [next] });
      await waitForTransactionReceipt(clients.eth, { hash: h1 });
      setBusy("2/3 Issuer trade on Ethereum Sepolia…");
      const h2 = await write.mutateAsync({ chainId: sepolia.id, address: D.issuer, abi: issuerAbi, functionName: "mint", args: [10n ** BigInt(DEC.stock)] });
      await waitForTransactionReceipt(clients.eth, { hash: h2 });
      // second chain: trade the sibling pool on Base to the same price
      setBusy("3/3 Sibling pool trade on Base Sepolia…");
      await switchChain.mutateAsync({ chainId: baseSepolia.id });
      const target = Math.round(Math.log((Number(next) / 10 ** DEC.usd) * 10 ** (DEC.usd - DEC.stock)) / Math.log(1.0001)) * (D.invert ? -1 : 1);
      const zeroForOne = target < (await readPoolTick(D.siblingPoolId));
      const h3 = await write.mutateAsync({
        chainId: baseSepolia.id,
        address: D.swapRouter,
        abi: swapRouterAbi,
        functionName: "swap",
        args: [siblingKey, { zeroForOne, amountSpecified: -(10n ** 30n), sqrtPriceLimitX96: sqrtAtTick(target) }, { takeClaims: false, settleUsingBurn: false }, "0x"],
      });
      await waitForTransactionReceipt(clients.base, { hash: h3 });
      setMsg({ ok: true, text: "News traded on two chains. The pool's fair price updates within a minute or two.", tx: h2 });
      qc.invalidateQueries({ queryKey: ["issuer"] });
      setTimeout(() => qc.invalidateQueries(), 6_000);
    } catch (e) {
      setMsg({ ok: false, text: friendlyError(e) });
    } finally {
      setBusy(null);
    }
  };

  return (
    <Card className="flex flex-col gap-4 border-accent/40">
      <div>
        <h2 className="text-lg font-semibold">Simulate weekend news</h2>
        <p className="text-muted">
          Owner only. Moves the issuer price on Ethereum Sepolia (now <span className="font-semibold text-ink tabular-nums">${usd(current)}</span>) and trades the sibling pool on Base to match — two chains, as the quorum requires.
        </p>
      </div>
      <div className="flex flex-wrap gap-2">
        {[200, -200, 500, -500].map((b) => (
          <Button key={b} variant={b > 0 ? "primary" : "ghost"} disabled={!!busy} onClick={() => move(b)}>
            {b > 0 ? "+" : "−"}{Math.abs(b) / 100}%
          </Button>
        ))}
      </div>
      {busy && <p role="status" className="text-sm text-muted">{busy}</p>}
      {msg && (
        <p role="status" className={`rounded-xl px-4 py-3 text-sm ${msg.ok ? "bg-good-soft text-good" : "bg-bad-soft text-bad"}`}>
          {msg.text} {msg.tx && <Ext href={explorer.eth(msg.tx)}>View trade</Ext>}
        </p>
      )}
    </Card>
  );
}
