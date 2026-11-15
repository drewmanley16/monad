import { NextResponse } from "next/server";
import { ensureSchema, sql } from "@/lib/db";

const TYPES = ["cafe", "restaurant", "retail"] as const;

export async function POST(req: Request) {
  const body = await req.json().catch(() => null);
  const business = String(body?.businessName ?? "").trim().slice(0, 80);
  const owner = String(body?.ownerName ?? "").trim().slice(0, 80);
  const email = String(body?.email ?? "").trim().toLowerCase().slice(0, 200);
  const type = TYPES.includes(body?.businessType) ? body.businessType : null;
  const payout = String(body?.payoutAddress ?? "").trim();

  if (!business || !owner || !type) return NextResponse.json({ error: "Please fill in every field." }, { status: 400 });
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return NextResponse.json({ error: "That email doesn't look right." }, { status: 400 });
  if (payout && !/^0x[0-9a-fA-F]{40}$/.test(payout)) return NextResponse.json({ error: "Payout account should look like 0x… (42 characters)." }, { status: 400 });

  try {
    await ensureSchema();
    const rows = await sql()`
      insert into merchants (business_name, owner_name, email, business_type, payout_address)
      values (${business}, ${owner}, ${email}, ${type}, ${payout || null})
      on conflict (email) do update set business_name = excluded.business_name, owner_name = excluded.owner_name,
        business_type = excluded.business_type, payout_address = excluded.payout_address
      returning id`;
    return NextResponse.json({ id: rows[0].id });
  } catch (e) {
    console.error(e);
    return NextResponse.json({ error: "We couldn't save your sign-up. Try again in a moment." }, { status: 500 });
  }
}
