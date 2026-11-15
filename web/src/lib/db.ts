import { neon } from "@neondatabase/serverless";

export type Merchant = {
  id: string;
  business_name: string;
  owner_name: string;
  email: string;
  business_type: "cafe" | "restaurant" | "retail";
  payout_address: string | null;
  created_at: string;
};

export function sql() {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error("DATABASE_URL is not set. Provision Neon: vercel integration add neon, then vercel env pull.");
  return neon(url);
}

let ready: Promise<unknown> | null = null;

/** Creates the merchants table on first use. */
export function ensureSchema() {
  ready ??= sql()`
    create table if not exists merchants (
      id uuid primary key default gen_random_uuid(),
      business_name text not null,
      owner_name text not null,
      email text not null unique,
      business_type text not null,
      payout_address text,
      created_at timestamptz not null default now()
    )`;
  return ready;
}
