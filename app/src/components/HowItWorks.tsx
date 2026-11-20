import { Card } from "./ui";

const STEPS = [
  {
    title: "Watch other chains",
    body: "When NYSE is closed, the real price still moves: the issuer mints and redeems shares on other chains. A Reactive Network contract listens to those trades.",
  },
  {
    title: "Push a fair price in",
    body: "It turns them into a fair price and calls this pool on Base — between trades, with no trusted bot or signer.",
  },
  {
    title: "Price every trade fairly",
    body: "Trades that move the pool toward the fair price are served. Trades that push it away pay more and are size-capped, so liquidity providers stay over the weekend.",
  },
];

export function HowItWorks() {
  return (
    <Card className="flex flex-col gap-4">
      <h2 className="text-lg font-semibold">How it works</h2>
      <ol className="flex flex-col gap-4">
        {STEPS.map((s, i) => (
          <li key={s.title} className="flex gap-3">
            <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-accent-soft font-bold text-accent" aria-hidden>
              {i + 1}
            </span>
            <span>
              <span className="block font-semibold">{s.title}</span>
              <span className="block text-muted">{s.body}</span>
            </span>
          </li>
        ))}
      </ol>
    </Card>
  );
}
