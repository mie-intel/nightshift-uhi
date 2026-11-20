import type { ReactNode } from "react";

export function Card({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <section className={`rounded-[var(--radius-card)] border border-line bg-surface p-6 shadow-[var(--shadow-card)] ${className}`}>
      {children}
    </section>
  );
}

export function Pill({ tone, children }: { tone: "good" | "bad" | "warn" | "neutral"; children: ReactNode }) {
  const map = {
    good: "bg-good-soft text-good",
    bad: "bg-bad-soft text-bad",
    warn: "bg-warn-soft text-warn",
    neutral: "bg-tint text-muted",
  };
  return <span className={`inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 py-1 text-sm font-medium ${map[tone]}`}>{children}</span>;
}

export function Ext({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a href={href} target="_blank" rel="noreferrer" className="font-medium text-accent underline decoration-accent/30 underline-offset-4 hover:decoration-accent">
      {children}
    </a>
  );
}

export function Skeleton({ className = "" }: { className?: string }) {
  return <span className={`inline-block animate-pulse rounded-md bg-tint ${className}`} aria-hidden />;
}

export function Button({
  children,
  onClick,
  disabled,
  variant = "primary",
  className = "",
}: {
  children: ReactNode;
  onClick?: () => void;
  disabled?: boolean;
  variant?: "primary" | "ghost";
  className?: string;
}) {
  const base = "inline-flex items-center justify-center gap-2 rounded-xl px-4 py-2.5 font-semibold transition-colors disabled:cursor-not-allowed disabled:opacity-50";
  const v =
    variant === "primary"
      ? "bg-accent text-white hover:bg-accent-hover"
      : "border border-field bg-surface text-ink hover:bg-tint";
  return (
    <button type="button" onClick={onClick} disabled={disabled} className={`${base} ${v} ${className}`}>
      {children}
    </button>
  );
}
