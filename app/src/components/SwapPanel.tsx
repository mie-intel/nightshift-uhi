import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useConnect, useConnection, useConnectors, useSwitchChain, useWriteContract } from "wagmi";
import { baseSepolia } from "viem/chains";
import { formatUnits, maxUint256, parseUnits, type Address } from "viem";
import { multicall, simulateContract, waitForTransactionReceipt } from "viem/actions";
import { BUY_ZERO_FOR_ONE, clients, D, DEC, hasFaucet, poolKey, explorer } from "../lib/config";
import { erc20Abi, faucetAbi, swapRouterAbi } from "../lib/abi";
import { friendlyError } from "../lib/errors";
import { pct, usd } from "../lib/format";
import { usePool } from "../hooks/usePool";
import { Button, Card, Ext, Pill } from "./ui";

const MIN_LIMIT = 4295128740n; // TickMath.MIN_SQRT_PRICE + 1
const MAX_LIMIT = 1461446703485210103287273052203988822378723970341n; // MAX_SQRT_PRICE - 1

type Side = "buy" | "sell";

function useBalances(owner?: Address) {
  return useQuery({
    queryKey: ["balances", owner],
    enabled: !!owner,
    refetchInterval: 15_000,
    queryFn: async () => {
      const [stock, usdBal, stockAllow, usdAllow] = await multicall(clients.base, {
        allowFailure: false,
        contracts: [
          { address: D.stock, abi: erc20Abi, functionName: "balanceOf", args: [owner!] },
          { address: D.usd, abi: erc20Abi, functionName: "balanceOf", args: [owner!] },
          { address: D.stock, abi: erc20Abi, functionName: "allowance", args: [owner!, D.swapRouter] },
          { address: D.usd, abi: erc20Abi, functionName: "allowance", args: [owner!, D.swapRouter] },
        ],
      });
      return { stock, usd: usdBal, stockAllow, usdAllow };
    },
  });
}

export function SwapPanel() {
  const [side, setSide] = useState<Side>("buy");
  const [amount, setAmount] = useState("100");
  const [busy, setBusy] = useState<string | null>(null);
  const [msg, setMsg] = useState<{ tone: "good" | "bad"; text: string; tx?: string } | null>(null);

  const { address, chainId, isConnected } = useConnection();
  const connectors = useConnectors();
  const connect = useConnect();
  const switchChain = useSwitchChain();
  const write = useWriteContract();
  const qc = useQueryClient();
  const pool = usePool();
  const bal = useBalances(address);

  const inToken = side === "buy" ? { addr: D.usd, sym: "dUSD", dec: DEC.usd } : { addr: D.stock, sym: "dSTOCK", dec: DEC.stock };
  const outSym = side === "buy" ? "dSTOCK" : "dUSD";
  const zeroForOne = side === "buy" ? BUY_ZERO_FOR_ONE : !BUY_ZERO_FOR_ONE;
  const quote = side === "buy" ? pool.data?.buy : pool.data?.sell;

  let amountRaw = 0n;
  try {
    amountRaw = amount ? parseUnits(amount, inToken.dec) : 0n;
  } catch {
    amountRaw = 0n;
  }
  const balance = bal.data ? (side === "buy" ? bal.data.usd : bal.data.stock) : 0n;
  const allowance = bal.data ? (side === "buy" ? bal.data.usdAllow : bal.data.stockAllow) : 0n;
  const price = pool.data?.poolPrice ?? 0;
  const estOut = price > 0 && amount ? (side === "buy" ? Number(amount) / price : Number(amount) * price) : 0;

  const run = async (label: string, fn: () => Promise<`0x${string}`>, done: string) => {
    setBusy(label);
    setMsg(null);
    try {
      const hash = await fn();
      await waitForTransactionReceipt(clients.base, { hash });
      setMsg({ tone: "good", text: done, tx: hash });
      await Promise.all([qc.invalidateQueries({ queryKey: ["balances"] }), qc.invalidateQueries({ queryKey: ["pool"] })]);
    } catch (e) {
      setMsg({ tone: "bad", text: friendlyError(e) });
    } finally {
      setBusy(null);
    }
  };

  const swapArgs = [
    poolKey,
    { zeroForOne, amountSpecified: -amountRaw, sqrtPriceLimitX96: zeroForOne ? MIN_LIMIT : MAX_LIMIT },
    { takeClaims: false, settleUsingBurn: false },
    "0x",
  ] as const;

  const doSwap = () =>
    run(
      "Swapping…",
      async () => {
        // simulate first so hook rejections show a clear message before the wallet pops up
        await simulateContract(clients.base, { account: address!, address: D.swapRouter, abi: swapRouterAbi, functionName: "swap", args: swapArgs });
        return write.mutateAsync({ chainId: baseSepolia.id, address: D.swapRouter, abi: swapRouterAbi, functionName: "swap", args: swapArgs });
      },
      side === "buy" ? "Bought dSTOCK." : "Sold dSTOCK.",
    );

  // one primary action at a time — the button always says what happens next
  let action: { label: string; onClick?: () => void; disabled?: boolean };
  if (!isConnected)
    action = { label: "Connect wallet", onClick: () => connectors[0] && connect.mutate({ connector: connectors[0] }), disabled: !connectors.length };
  else if (chainId !== baseSepolia.id)
    action = { label: "Switch to Base Sepolia", onClick: () => switchChain.mutate({ chainId: baseSepolia.id }) };
  else if (balance === 0n && hasFaucet)
    action = {
      label: "Get free demo tokens",
      onClick: () => run("Claiming…", () => write.mutateAsync({ chainId: baseSepolia.id, address: D.faucet, abi: faucetAbi, functionName: "claim" }), "Demo tokens received."),
    };
  else if (amountRaw === 0n) action = { label: "Enter an amount", disabled: true };
  else if (amountRaw > balance) action = { label: `Not enough ${inToken.sym}`, disabled: true };
  else if (allowance < amountRaw)
    action = {
      label: `Allow ${inToken.sym}`,
      onClick: () => run("Approving…", () => write.mutateAsync({ chainId: baseSepolia.id, address: inToken.addr, abi: erc20Abi, functionName: "approve", args: [D.swapRouter, maxUint256] }), `${inToken.sym} allowed. Now swap.`),
    };
  else action = { label: side === "buy" ? "Buy dSTOCK" : "Sell dSTOCK", onClick: doSwap };

  return (
    <Card className="flex flex-col gap-5">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold">Try a trade</h2>
        <span className="text-sm text-muted">Base Sepolia</span>
      </div>

      <div className="grid grid-cols-2 gap-1 rounded-xl bg-tint p-1" role="tablist" aria-label="Buy or sell">
        {(["buy", "sell"] as Side[]).map((s) => (
          <button
            key={s}
            role="tab"
            aria-selected={side === s}
            onClick={() => { setSide(s); setAmount(s === "buy" ? "100" : "1"); setMsg(null); }}
            className={`rounded-lg py-2 font-semibold transition-colors ${side === s ? "bg-surface text-ink shadow-sm" : "text-muted hover:text-ink"}`}
          >
            {s === "buy" ? "Buy dSTOCK" : "Sell dSTOCK"}
          </button>
        ))}
      </div>

      <label className="block">
        <span className="mb-1.5 flex justify-between text-sm text-muted">
          <span>You pay</span>
          {bal.data && (
            <button className="hover:text-ink" onClick={() => setAmount(formatUnits(balance, inToken.dec))}>
              Balance: <span className="tabular-nums">{usd(Number(formatUnits(balance, inToken.dec)))}</span>
            </button>
          )}
        </span>
        <div className="flex items-center rounded-xl border border-field bg-surface px-4 focus-within:outline-2 focus-within:outline-accent">
          <input
            inputMode="decimal"
            value={amount}
            onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))}
            className="w-full bg-transparent py-3 text-2xl font-semibold tabular-nums outline-none"
            aria-label={`Amount of ${inToken.sym}`}
          />
          <span className="font-semibold text-muted">{inToken.sym}</span>
        </div>
      </label>

      <div className="space-y-2 rounded-xl bg-tint/60 p-4 text-sm">
        <div className="flex justify-between">
          <span className="text-muted">You get about</span>
          <span className="font-semibold tabular-nums">{estOut ? `${usd(estOut, side === "buy" ? 4 : 2)} ${outSym}` : "—"}</span>
        </div>
        <div className="flex items-center justify-between">
          <span className="text-muted">Fee</span>
          <span className="flex items-center gap-2">
            <span className="font-semibold tabular-nums">{quote ? pct(quote.fee) : "—"}</span>
            {quote && (quote.away ? <Pill tone="bad">Away</Pill> : <Pill tone="good">Toward</Pill>)}
          </span>
        </div>
        {quote?.away && (
          <p className="text-muted">
            This trade moves the price away from fair value, so it costs more
            {pool.data && pool.data.regime !== 0 ? " and big sizes are blocked while the market is closed." : "."}
          </p>
        )}
      </div>

      <Button onClick={action.onClick} disabled={action.disabled || !!busy} className="w-full py-3.5 text-lg">
        {busy ?? action.label}
      </Button>

      {msg && (
        <p role="status" className={`rounded-xl px-4 py-3 text-sm ${msg.tone === "good" ? "bg-good-soft text-good" : "bg-bad-soft text-bad"}`}>
          {msg.text} {msg.tx && <Ext href={explorer.base(msg.tx)}>View transaction</Ext>}
        </p>
      )}
      {!hasFaucet && isConnected && <p className="text-sm text-muted">Demo faucet not deployed yet — only the deployer wallet holds demo tokens.</p>}
    </Card>
  );
}
