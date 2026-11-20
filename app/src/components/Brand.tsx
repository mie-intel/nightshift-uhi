export function Logo() {
  return (
    <svg viewBox="0 0 32 32" className="h-8 w-8" aria-hidden>
      <circle cx="16" cy="16" r="14" fill="var(--color-accent)" />
      <circle cx="21.5" cy="11.5" r="10" fill="var(--color-canvas)" />
    </svg>
  );
}

export function Brand() {
  return (
    <div className="flex items-center gap-3">
      <Logo />
      <span className="text-xl font-bold tracking-tight">NightShift</span>
      <span className="hidden rounded-full bg-tint px-2.5 py-0.5 text-sm text-muted sm:inline">Testnet demo</span>
    </div>
  );
}
