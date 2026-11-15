import Link from "next/link";

export function Nav() {
  return (
    <header className="sticky top-0 z-10 border-b border-black/5 bg-white/85 backdrop-blur">
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-6">
        <Link href="/" className="font-semibold tracking-tight">Tapnad</Link>
        <nav className="hidden gap-7 text-sm text-neutral-600 sm:flex">
          <Link href="/#how" className="hover:text-neutral-900">How it works</Link>
          <Link href="/#features" className="hover:text-neutral-900">Features</Link>
          <Link href="/#pricing" className="hover:text-neutral-900">Pricing</Link>
        </nav>
        <Link href="/signup" className="rounded-md bg-neutral-900 px-3.5 py-2 text-sm font-semibold text-white hover:bg-neutral-700">
          Get started
        </Link>
      </div>
    </header>
  );
}

export function Footer() {
  return (
    <footer className="border-t border-black/5">
      <div className="mx-auto flex max-w-6xl flex-col gap-2 px-6 py-8 text-xs text-neutral-500 sm:flex-row sm:justify-between">
        <span>© {new Date().getFullYear()} Tapnad</span>
        <span>Test mode: payments use test funds and settle on the Monad testnet.</span>
      </div>
    </footer>
  );
}
