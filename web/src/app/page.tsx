import Image from "next/image";
import Link from "next/link";
import { Footer, Nav } from "@/components/Chrome";

const features = [
  { title: "Tap to pay", body: "Customers hold their phone to your register and approve with Face ID. No card reader to buy." },
  { title: "Paid in under a second", body: "Money lands in your account the moment it's approved. No batches, no 2–3 day settlement." },
  { title: "Split the bill", body: "Divide any order up to four ways. Each phone taps in turn and the register keeps track." },
  { title: "Loyalty built in", body: "Every eighth drink is on the house. Rewards apply automatically when a returning customer taps." },
  { title: "Kitchen order board", body: "Paid orders get a number and move from New to Preparing to Ready to Picked up." },
  { title: "Refunds in one click", body: "Send money back from the order screen. It shows up on the customer's phone right away." },
  { title: "Customer display", body: "Put the order, total and a thank-you on a second screen facing your customer." },
  { title: "Reports & close-out", body: "Sales, tips, top items and an end-of-day summary you can export to CSV." },
];

const steps = [
  { n: "1", title: "Create your register", body: "Tell us your business name and pick a menu to start from." },
  { n: "2", title: "Open Tapnad POS on your Mac", body: "One click sets up your name, payouts and menu." },
  { n: "3", title: "Start taking payments", body: "Customers pay with the Tapnad app. You're paid instantly." },
];

export default function Home() {
  return (
    <main>
      <Nav />

      <section className="mx-auto max-w-6xl px-6 pt-20 pb-16 text-center">
        <p className="mb-5 inline-block rounded-full border border-black/10 px-3 py-1 text-xs font-medium text-neutral-600">
          Now in test mode · free to try
        </p>
        <h1 className="mx-auto max-w-3xl text-5xl font-semibold tracking-tight text-neutral-900 sm:text-6xl">
          Tap to pay. Paid before the receipt prints.
        </h1>
        <p className="mx-auto mt-6 max-w-xl text-lg text-neutral-600">
          Tapnad is a point of sale for cafés, restaurants and shops. Customers tap their phone, and the money is
          yours in under a second.
        </p>
        <div className="mt-9 flex justify-center gap-3">
          <Link href="/signup" className="rounded-md bg-neutral-900 px-5 py-3 text-sm font-semibold text-white hover:bg-neutral-700">
            Create your register
          </Link>
          <a href="#how" className="rounded-md border border-black/10 px-5 py-3 text-sm font-semibold text-neutral-900 hover:bg-neutral-50">
            How it works
          </a>
        </div>
      </section>

      <section className="mx-auto max-w-6xl px-6">
        <div className="relative">
          <div className="overflow-hidden rounded-xl border border-black/10 shadow-[0_30px_80px_-30px_rgba(0,0,0,0.25)]">
            <Image src="/pos.jpg" alt="Tapnad POS checkout screen" width={1800} height={1764} priority className="w-full" />
          </div>
          <div className="absolute -bottom-10 right-4 hidden w-56 overflow-hidden rounded-[2rem] border-[6px] border-neutral-900 shadow-2xl md:block lg:-right-8 lg:w-64">
            <Image src="/wallet.jpg" alt="Tapnad Wallet on iPhone" width={552} height={1200} className="w-full" />
          </div>
        </div>
      </section>

      <section className="mx-auto mt-32 max-w-6xl px-6">
        <div className="grid gap-px overflow-hidden rounded-xl border border-black/10 bg-black/10 sm:grid-cols-3">
          {[
            ["< 1 s", "from tap to money in your account"],
            ["$0", "hardware — your Mac is the register"],
            ["0", "chargebacks or settlement holds"],
          ].map(([big, small]) => (
            <div key={big} className="bg-white p-8">
              <div className="text-4xl font-semibold tracking-tight">{big}</div>
              <div className="mt-2 text-sm text-neutral-600">{small}</div>
            </div>
          ))}
        </div>
      </section>

      <section id="how" className="mx-auto mt-28 max-w-6xl scroll-mt-20 px-6">
        <h2 className="text-3xl font-semibold tracking-tight">Up and running in five minutes</h2>
        <div className="mt-10 grid gap-8 sm:grid-cols-3">
          {steps.map((s) => (
            <div key={s.n}>
              <div className="flex h-9 w-9 items-center justify-center rounded-full bg-neutral-900 text-sm font-semibold text-white">{s.n}</div>
              <h3 className="mt-4 font-semibold">{s.title}</h3>
              <p className="mt-1.5 text-sm leading-6 text-neutral-600">{s.body}</p>
            </div>
          ))}
        </div>
      </section>

      <section id="features" className="mx-auto mt-28 max-w-6xl scroll-mt-20 px-6">
        <h2 className="text-3xl font-semibold tracking-tight">Everything a counter needs</h2>
        <div className="mt-10 grid gap-x-10 gap-y-9 sm:grid-cols-2 lg:grid-cols-4">
          {features.map((f) => (
            <div key={f.title} className="border-t border-black/10 pt-5">
              <h3 className="font-semibold">{f.title}</h3>
              <p className="mt-1.5 text-sm leading-6 text-neutral-600">{f.body}</p>
            </div>
          ))}
        </div>
      </section>

      <section id="pricing" className="mx-auto mt-28 max-w-6xl scroll-mt-20 px-6">
        <div className="rounded-2xl bg-neutral-50 px-8 py-14 sm:px-14">
          <div className="grid items-center gap-10 sm:grid-cols-2">
            <div>
              <h2 className="text-3xl font-semibold tracking-tight">Simple pricing</h2>
              <p className="mt-3 text-neutral-600">Free while we&apos;re in test mode. No monthly fee, no hardware, no contract.</p>
            </div>
            <ul className="space-y-3 text-sm">
              {["Unlimited registers and items", "Instant payouts to your account", "Loyalty, split bills and refunds included", "Export your data any time"].map((t) => (
                <li key={t} className="flex gap-3">
                  <span className="mt-0.5 text-neutral-900">✓</span>
                  <span className="text-neutral-700">{t}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </section>

      <section className="mx-auto mt-28 max-w-6xl px-6 pb-24 text-center">
        <h2 className="text-4xl font-semibold tracking-tight">Ready when you are.</h2>
        <p className="mt-3 text-neutral-600">Set up your register now and take your first payment today.</p>
        <Link href="/signup" className="mt-8 inline-block rounded-md bg-neutral-900 px-6 py-3 text-sm font-semibold text-white hover:bg-neutral-700">
          Create your register
        </Link>
      </section>

      <Footer />
    </main>
  );
}

