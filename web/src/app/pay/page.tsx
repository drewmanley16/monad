"use client";

import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import { createPublicClient, createWalletClient, encodeFunctionData, http, isAddress, type Address, type Hex } from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { EXPLORER_TX, MONADPAY, PAID_TOPIC, RPC, WS, monadPayAbi, monadTestnet, parseMon, topicFor, usd } from "@/lib/chain";

type Phase = "ready" | "paying" | "paid" | "error";
type Step = "Proposed" | "Voted" | "Finalized";
const STEPS: Step[] = ["Proposed", "Voted", "Finalized"];

const publicClient = createPublicClient({ chain: monadTestnet, transport: http(RPC) });

/** Browser wallet: a key generated on this phone and kept in localStorage (test mode only). */
function useBrowserWallet() {
  const [key, setKey] = useState<Hex | null>(null);
  useEffect(() => {
    let k: string | null = null;
    try { k = localStorage.getItem("tapnad.key"); } catch {}
    if (!k || !/^0x[0-9a-f]{64}$/i.test(k)) {
      k = generatePrivateKey();
      try { localStorage.setItem("tapnad.key", k); } catch {}
    }
    setKey(k as Hex);
  }, []);
  return useMemo(() => (key ? privateKeyToAccount(key) : null), [key]);
}

function Checkout() {
  const q = useSearchParams();
  const merchant = q.get("to") ?? "";
  const amount = useMemo(() => { try { return parseMon(q.get("amt") ?? "0"); } catch { return 0n; } }, [q]);
  const invoice = (q.get("inv") ?? "") as Hex;
  const name = q.get("name") || "Merchant";
  const memo = q.get("memo") ?? "";
  const valid = isAddress(merchant) && amount > 0n && /^0x[0-9a-f]{64}$/i.test(invoice);

  const account = useBrowserWallet();
  const [balance, setBalance] = useState<bigint | null>(null);
  const [tip, setTip] = useState(0);
  const [phase, setPhase] = useState<Phase>("ready");
  const [error, setError] = useState<string | null>(null);
  const [already, setAlready] = useState(false);
  const [funding, setFunding] = useState(false);
  const [times, setTimes] = useState<Partial<Record<Step, number>>>({});
  const [tx, setTx] = useState<Hex | null>(null);
  const wsRef = useRef<WebSocket | null>(null);

  const total = amount + (amount * BigInt(tip)) / 100n;
  const items = memo.replace(/^#\d+\s*/, "").split(",").map((s) => s.trim()).filter(Boolean);

  const refresh = useCallback(async () => {
    if (account) setBalance(await publicClient.getBalance({ address: account.address }).catch(() => null));
  }, [account]);

  useEffect(() => { refresh(); const t = setInterval(refresh, 4000); return () => clearInterval(t); }, [refresh]);

  // Was this invoice already paid (e.g. the QR was scanned twice)?
  useEffect(() => {
    if (!valid) return;
    publicClient.request({
      method: "eth_getLogs",
      params: [{ address: MONADPAY, fromBlock: "earliest" as never, topics: [PAID_TOPIC, topicFor(merchant as Address), invoice] }],
    }).then((logs) => { if ((logs as unknown[]).length) setAlready(true); }).catch(() => {});
  }, [valid, merchant, invoice]);

  useEffect(() => () => wsRef.current?.close(), []);

  async function addMoney() {
    if (!account) return;
    setFunding(true); setError(null);
    const res = await fetch("/api/faucet", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ address: account.address }) });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) setError(data.error ?? "Couldn't add test money.");
    // poll quickly until it lands
    for (let i = 0; i < 10 && res.ok; i++) {
      await new Promise((r) => setTimeout(r, 700));
      const b = await publicClient.getBalance({ address: account.address }).catch(() => null);
      if (b !== null && b >= total) { setBalance(b); break; }
      setBalance(b);
    }
    // Monad checks balances against slightly delayed state; give fresh funds a moment to become spendable.
    if (res.ok) await new Promise((r) => setTimeout(r, 2500));
    setFunding(false);
  }

  /** Subscribe to this invoice's Paid log (all commit states) before broadcasting. */
  function watch(t0: { v: number }) {
    return new Promise<void>((resolve) => {
      const ws = new WebSocket(WS);
      wsRef.current = ws;
      const timer = setTimeout(resolve, 2500);
      ws.onopen = () => ws.send(JSON.stringify({
        jsonrpc: "2.0", id: 1, method: "eth_subscribe",
        params: ["monadLogs", { address: MONADPAY, topics: [PAID_TOPIC, topicFor(merchant as Address), invoice] }],
      }));
      ws.onmessage = (m) => {
        const msg = JSON.parse(m.data);
        if (msg.id === 1) { clearTimeout(timer); resolve(); return; }
        const state = msg.params?.result?.commitState as Step | undefined;
        if (!state || !STEPS.includes(state)) return;
        const ms = Math.round(performance.now() - t0.v);
        setTimes((prev) => {
          const next = { ...prev };
          for (const s of STEPS.slice(0, STEPS.indexOf(state) + 1)) next[s] ??= ms;
          return next;
        });
        setPhase("paid");
      };
    });
  }

  async function pay() {
    if (!account || !valid) return;
    setPhase("paying"); setError(null); setTimes({});
    try {
      const data = encodeFunctionData({ abi: monadPayAbi, functionName: "pay", args: [merchant as Address, invoice, memo] });
      const gas = await publicClient.estimateGas({ account: account.address, to: MONADPAY, value: total, data });
      const wallet = createWalletClient({ account, chain: monadTestnet, transport: http(RPC) });
      const t0 = { v: performance.now() };
      await watch(t0);
      t0.v = performance.now();
      let hash: Hex | undefined;
      for (let attempt = 0; ; attempt++) {
        try {
          hash = await wallet.sendTransaction({ to: MONADPAY, value: total, data, gas: gas + gas / 10n });
          break;
        } catch (e) {
          // funds that just arrived aren't spendable for ~1–2 s; retry a few times
          if (attempt < 4 && e instanceof Error && /insufficient balance/i.test(e.message)) { await new Promise((r) => setTimeout(r, 1000)); continue; }
          throw e;
        }
      }
      setTx(hash);
      // safety net if the socket misses the update
      setTimeout(() => setPhase((p) => (p === "paying" ? "paid" : p)), 6000);
    } catch (e) {
      setPhase("error");
      setError(e instanceof Error ? e.message.split("\n")[0] : "Payment failed.");
    }
  }

  if (!valid) {
    return <Shell><p className="text-center text-neutral-600">This payment link isn&apos;t valid. Ask the register to show a new code.</p></Shell>;
  }

  const insufficient = balance !== null && balance < total;

  if (phase === "paid") {
    return (
      <Shell>
        <div className="flex flex-col items-center text-center">
          <div className="flex h-20 w-20 items-center justify-center rounded-full bg-neutral-900 text-4xl text-white">✓</div>
          <h1 className="mt-5 text-2xl font-semibold">Paid {usd(total)}</h1>
          <p className="mt-1 text-neutral-600">{name}</p>
        </div>
        <div className="mt-8 space-y-3 rounded-xl border border-black/10 p-5">
          {STEPS.map((s) => (
            <div key={s} className="flex items-center gap-3 text-sm">
              <span className={`h-2 w-2 rounded-full ${times[s] !== undefined ? "bg-neutral-900" : "bg-neutral-300"}`} />
              <span className={times[s] !== undefined ? "text-neutral-900" : "text-neutral-400"}>{s}</span>
              <span className="ml-auto font-mono tabular-nums text-neutral-700">{times[s] !== undefined ? `+${times[s]} ms` : "…"}</span>
            </div>
          ))}
        </div>
        <p className="mt-3 text-center text-xs text-neutral-500">Settled on Monad in under a second.</p>
        {tx && <a href={EXPLORER_TX + tx} className="mt-6 block text-center text-sm font-medium text-neutral-900 underline underline-offset-4">View receipt</a>}
      </Shell>
    );
  }

  return (
    <Shell>
      <div className="text-center">
        <p className="text-sm font-medium text-neutral-500">{name}</p>
        <h1 className="mt-2 text-5xl font-semibold tracking-tight tabular-nums">{usd(total)}</h1>
        {items.length > 0 && <p className="mx-auto mt-3 max-w-xs text-sm text-neutral-600">{items.join(" · ")}</p>}
      </div>

      {already ? (
        <div className="mt-10 rounded-xl border border-black/10 p-5 text-center text-sm text-neutral-700">This order has already been paid. ✓</div>
      ) : (
        <>
          <div className="mt-8 grid grid-cols-4 gap-2">
            {[0, 10, 15, 20].map((t) => (
              <button key={t} onClick={() => setTip(t)} disabled={phase === "paying"}
                className={`rounded-lg border py-2.5 text-sm font-medium ${tip === t ? "border-neutral-900 bg-neutral-900 text-white" : "border-black/10 text-neutral-700"}`}>
                {t === 0 ? "No tip" : `${t}%`}
              </button>
            ))}
          </div>

          <div className="mt-4 flex items-center justify-between rounded-xl bg-neutral-100 px-4 py-3.5 text-sm">
            <div>
              <div className="font-medium text-neutral-900">Tapnad balance</div>
              <div className="text-neutral-500">{balance === null ? "…" : usd(balance)}</div>
            </div>
            <button onClick={addMoney} disabled={funding || !account}
              className="rounded-md border border-black/15 bg-white px-3 py-2 text-xs font-semibold text-neutral-900 disabled:opacity-50">
              {funding ? "Adding…" : "Add $10 test money"}
            </button>
          </div>

          <button onClick={pay} disabled={phase === "paying" || insufficient || !account}
            className="mt-6 w-full rounded-xl bg-neutral-900 py-4 text-base font-semibold text-white disabled:opacity-40">
            {phase === "paying" ? "Paying…" : `Pay ${usd(total)}`}
          </button>
          {insufficient && <p className="mt-3 text-center text-sm text-neutral-600">Add test money to pay.</p>}
          {error && <p className="mt-3 text-center text-sm text-red-600">{error}</p>}
        </>
      )}
    </Shell>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <main className="min-h-[100dvh] bg-white">
      <div className="mx-auto flex min-h-[100dvh] max-w-md flex-col px-6 pt-10 pb-8">
        <div className="mb-10 flex items-center justify-between text-sm">
          <span className="font-semibold">Tapnad</span>
          <span className="rounded-full border border-black/10 px-2 py-0.5 text-[10px] font-semibold tracking-wide text-neutral-500">TEST MODE</span>
        </div>
        <div className="flex-1">{children}</div>
        <p className="mt-10 text-center text-[11px] text-neutral-400">Test money only · settles on the Monad testnet</p>
      </div>
    </main>
  );
}

export default function PayPage() {
  return <Suspense><Checkout /></Suspense>;
}
