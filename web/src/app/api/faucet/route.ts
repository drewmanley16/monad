import { NextResponse } from "next/server";
import { createPublicClient, createWalletClient, http, isAddress, parseEther, type Address, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { monadTestnet, RPC } from "@/lib/chain";
import { sql } from "@/lib/db";

const DRIP = parseEther("0.1");        // $10 at the display rate
const MAX_BALANCE = parseEther("0.05"); // only top up nearly-empty wallets
const DAILY_LIMIT = 3;

export async function POST(req: Request) {
  const key = process.env.FAUCET_PRIVATE_KEY as Hex | undefined;
  if (!key) return NextResponse.json({ error: "Test money is offline right now." }, { status: 503 });

  const body = await req.json().catch(() => null);
  const address = String(body?.address ?? "");
  if (!isAddress(address)) return NextResponse.json({ error: "Invalid wallet." }, { status: 400 });

  const pub = createPublicClient({ chain: monadTestnet, transport: http(RPC) });
  const balance = await pub.getBalance({ address: address as Address });
  if (balance > MAX_BALANCE) return NextResponse.json({ error: "You already have test money." }, { status: 429 });

  const db = sql();
  await db`create table if not exists faucet_claims (address text not null, created_at timestamptz not null default now())`;
  const [{ n }] = (await db`select count(*)::int as n from faucet_claims
    where lower(address) = ${address.toLowerCase()} and created_at > now() - interval '1 day'`) as { n: number }[];
  if (n >= DAILY_LIMIT) return NextResponse.json({ error: "Daily test-money limit reached." }, { status: 429 });

  try {
    const wallet = createWalletClient({ account: privateKeyToAccount(key), chain: monadTestnet, transport: http(RPC) });
    const hash = await wallet.sendTransaction({ to: address as Address, value: DRIP, gas: 21000n });
    await db`insert into faucet_claims (address) values (${address})`;
    return NextResponse.json({ hash });
  } catch (e) {
    console.error(e);
    return NextResponse.json({ error: "Couldn't send test money. Try again." }, { status: 500 });
  }
}
