/** Map revert data (incl. v4 WrappedError payloads) to plain-language messages. */
const KNOWN: [string, string][] = [
  ["879e675b", "Blocked: this trade pushes the price too far away from the fair price while the market is closed. Try a smaller amount."],
  ["cb012c01", "Blocked: this trade would overshoot the fair price. Try a smaller amount."],
  ["8fe89dfc", "Trading is paused (halted) for this pool right now."],
  ["e86f59ea", "You already claimed demo tokens recently. Try again later."],
];

export function friendlyError(e: unknown): string {
  const text = String((e as { message?: string })?.message ?? e).toLowerCase();
  const raw = JSON.stringify(e, (_k, v) => (typeof v === "bigint" ? v.toString() : v)).toLowerCase();
  for (const [sel, msg] of KNOWN) if (text.includes(sel) || raw.includes(sel)) return msg;
  if (text.includes("user rejected") || text.includes("denied")) return "You cancelled the request in your wallet.";
  if (text.includes("insufficient funds")) return "Not enough Base Sepolia ETH for gas.";
  if (text.includes("transfer amount exceeds balance") || text.includes("e450d38c")) return "Not enough tokens for this amount.";
  const short = (e as { shortMessage?: string })?.shortMessage;
  return short ?? "Something went wrong. Please try again.";
}
