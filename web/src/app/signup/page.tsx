"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { Nav } from "@/components/Chrome";

const types = [
  { id: "cafe", title: "Café", body: "Coffee, tea, pastries. Drink options and loyalty stamps." },
  { id: "restaurant", title: "Restaurant", body: "Mains, sides and drinks. Split bills and a kitchen board." },
  { id: "retail", title: "Shop", body: "Merch and goods with stock tracking." },
] as const;

export default function Signup() {
  const router = useRouter();
  const [step, setStep] = useState(0);
  const [form, setForm] = useState({ businessName: "", ownerName: "", email: "", businessType: "cafe", payoutAddress: "" });
  const [payoutMode, setPayoutMode] = useState<"new" | "existing">("new");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const set = (k: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement>) => setForm({ ...form, [k]: e.target.value });

  const canNext = step === 0 ? form.businessName && form.ownerName && /\S+@\S+\.\S+/.test(form.email) : true;

  async function submit() {
    setSaving(true);
    setError(null);
    const res = await fetch("/api/signup", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ...form, payoutAddress: payoutMode === "existing" ? form.payoutAddress : "" }),
    });
    const data = await res.json().catch(() => ({}));
    setSaving(false);
    if (!res.ok) return setError(data.error ?? "Something went wrong.");
    router.push(`/welcome/${data.id}`);
  }

  return (
    <main className="min-h-screen bg-neutral-50">
      <Nav />
      <div className="mx-auto max-w-xl px-6 py-14">
        <div className="mb-8 flex gap-2">
          {["Your business", "Menu", "Payouts"].map((label, i) => (
            <div key={label} className="flex-1">
              <div className={`h-1 rounded-full ${i <= step ? "bg-neutral-900" : "bg-black/10"}`} />
              <div className={`mt-2 text-xs ${i === step ? "font-semibold text-neutral-900" : "text-neutral-500"}`}>{label}</div>
            </div>
          ))}
        </div>

        <div className="rounded-xl border border-black/10 bg-white p-8">
          {step === 0 && (
            <div className="space-y-5">
              <h1 className="text-2xl font-semibold tracking-tight">Create your register</h1>
              <Field label="Business name" value={form.businessName} onChange={set("businessName")} placeholder="Corner Coffee" autoFocus />
              <Field label="Your name" value={form.ownerName} onChange={set("ownerName")} placeholder="Alex Rivera" />
              <Field label="Email" type="email" value={form.email} onChange={set("email")} placeholder="alex@cornercoffee.com" />
            </div>
          )}

          {step === 1 && (
            <div className="space-y-5">
              <h1 className="text-2xl font-semibold tracking-tight">What do you sell?</h1>
              <p className="text-sm text-neutral-600">We&apos;ll start you with a sample menu. You can edit every item in the app.</p>
              <div className="space-y-3">
                {types.map((t) => (
                  <button
                    key={t.id}
                    onClick={() => setForm({ ...form, businessType: t.id })}
                    className={`w-full rounded-lg border p-4 text-left transition ${form.businessType === t.id ? "border-neutral-900 ring-1 ring-neutral-900" : "border-black/10 hover:border-black/30"}`}
                  >
                    <div className="font-semibold">{t.title}</div>
                    <div className="mt-0.5 text-sm text-neutral-600">{t.body}</div>
                  </button>
                ))}
              </div>
            </div>
          )}

          {step === 2 && (
            <div className="space-y-5">
              <h1 className="text-2xl font-semibold tracking-tight">Where should we send your money?</h1>
              <div className="space-y-3">
                <Choice on={payoutMode === "new"} onClick={() => setPayoutMode("new")} title="Create a payout account for me"
                  body="Tapnad sets one up on your Mac when you open the app. Easiest option." />
                <Choice on={payoutMode === "existing"} onClick={() => setPayoutMode("existing")} title="I already have an account"
                  body="Paste your Tapnad or Monad account address." />
              </div>
              {payoutMode === "existing" && (
                <Field label="Account address" value={form.payoutAddress} onChange={set("payoutAddress")} placeholder="0x…" mono />
              )}
              {error && <p className="text-sm text-red-600">{error}</p>}
            </div>
          )}

          <div className="mt-8 flex justify-between">
            <button onClick={() => setStep(step - 1)} className={`rounded-md px-4 py-2.5 text-sm font-semibold text-neutral-700 hover:bg-neutral-100 ${step === 0 ? "invisible" : ""}`}>
              Back
            </button>
            {step < 2 ? (
              <button disabled={!canNext} onClick={() => setStep(step + 1)}
                className="rounded-md bg-neutral-900 px-5 py-2.5 text-sm font-semibold text-white enabled:hover:bg-neutral-700 disabled:opacity-30">
                Continue
              </button>
            ) : (
              <button disabled={saving} onClick={submit}
                className="rounded-md bg-neutral-900 px-5 py-2.5 text-sm font-semibold text-white enabled:hover:bg-neutral-700 disabled:opacity-50">
                {saving ? "Creating…" : "Create register"}
              </button>
            )}
          </div>
        </div>
        <p className="mt-6 text-center text-xs text-neutral-500">Test mode: no real money moves. Free while in beta.</p>
      </div>
    </main>
  );
}

function Field({ label, mono, ...props }: { label: string; mono?: boolean } & React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <label className="block">
      <span className="text-sm font-medium text-neutral-800">{label}</span>
      <input {...props} className={`mt-1.5 w-full rounded-md border border-black/15 px-3 py-2.5 text-sm outline-none focus:border-neutral-900 focus:ring-1 focus:ring-neutral-900 ${mono ? "font-mono" : ""}`} />
    </label>
  );
}

function Choice({ on, onClick, title, body }: { on: boolean; onClick: () => void; title: string; body: string }) {
  return (
    <button onClick={onClick} className={`w-full rounded-lg border p-4 text-left transition ${on ? "border-neutral-900 ring-1 ring-neutral-900" : "border-black/10 hover:border-black/30"}`}>
      <div className="font-semibold">{title}</div>
      <div className="mt-0.5 text-sm text-neutral-600">{body}</div>
    </button>
  );
}
