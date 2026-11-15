import { notFound } from "next/navigation";
import { Nav } from "@/components/Chrome";
import { sql, type Merchant } from "@/lib/db";

export const dynamic = "force-dynamic";

const REPO = "https://github.com/drewmanley16/monad";

export default async function Welcome({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const rows = (await sql()`select * from merchants where id = ${id}`) as Merchant[];
  const m = rows[0];
  if (!m) notFound();

  const setup = new URL("tapnadpos://setup");
  setup.searchParams.set("name", m.business_name);
  setup.searchParams.set("template", m.business_type);
  if (m.payout_address) setup.searchParams.set("payout", m.payout_address);

  return (
    <main className="min-h-screen bg-neutral-50">
      <Nav />
      <div className="mx-auto max-w-xl px-6 py-14">
        <div className="rounded-xl border border-black/10 bg-white p-8">
          <div className="flex h-11 w-11 items-center justify-center rounded-full bg-neutral-900 text-lg text-white">✓</div>
          <h1 className="mt-5 text-2xl font-semibold tracking-tight">{m.business_name} is ready, {m.owner_name.split(" ")[0]}.</h1>
          <p className="mt-2 text-sm text-neutral-600">Three quick steps and you&apos;re taking payments.</p>

          <ol className="mt-8 space-y-6">
            <Step n={1} title="Install Tapnad POS on your Mac" body="Build it from the source while we're in beta (macOS 15 or later).">
              <a href={REPO} className="text-sm font-semibold text-neutral-900 underline underline-offset-4">Get Tapnad POS</a>
            </Step>
            <Step n={2} title="Set up your register" body="Opens Tapnad POS with your business name, menu and payouts filled in.">
              <a href={setup.toString()} className="inline-block rounded-md bg-neutral-900 px-4 py-2.5 text-sm font-semibold text-white hover:bg-neutral-700">
                Open in Tapnad POS
              </a>
            </Step>
            <Step n={3} title="Have customers use Tapnad Wallet" body="They tap their iPhone to your Mac and approve with Face ID.">
              <a href={REPO} className="text-sm font-semibold text-neutral-900 underline underline-offset-4">Get the wallet app</a>
            </Step>
          </ol>
        </div>
        <p className="mt-6 text-center text-xs text-neutral-500">We sent nothing to {m.email} yet — this page is your setup link. Bookmark it.</p>
      </div>
    </main>
  );
}

function Step({ n, title, body, children }: { n: number; title: string; body: string; children: React.ReactNode }) {
  return (
    <li className="flex gap-4">
      <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full border border-black/15 text-xs font-semibold">{n}</div>
      <div className="space-y-2">
        <div className="font-semibold">{title}</div>
        <p className="text-sm text-neutral-600">{body}</p>
        {children}
      </div>
    </li>
  );
}
