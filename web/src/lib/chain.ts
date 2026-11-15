import { defineChain, pad, parseAbi, type Address, type Hex } from "viem";

export const RPC = "https://testnet-rpc.monad.xyz";
export const WS = "wss://testnet-rpc.monad.xyz";
export const EXPLORER_TX = "https://testnet.monadexplorer.com/tx/";
export const MONADPAY = "0xF825f70E27b7f65bB44475FB4530b7c09245F128" as Address;
export const PAID_TOPIC = "0xefb6650ea952a1f15b25c0abf0e65623721748fe689043ee32d4e74d79fbc25f" as Hex;

/** Fixed display rate for testnet MON (no market price) — matches the iOS/macOS apps. */
export const USD_PER_MON = 100;

export const monadTestnet = defineChain({
  id: 10143,
  name: "Monad Testnet",
  nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
  rpcUrls: { default: { http: [RPC], webSocket: [WS] } },
  blockExplorers: { default: { name: "Monad Explorer", url: "https://testnet.monadexplorer.com" } },
  testnet: true,
});

export const monadPayAbi = parseAbi(["function pay(address merchant, bytes32 invoiceId, string memo) payable"]);

export const usd = (wei: bigint) =>
  (Number(wei) / 1e18 * USD_PER_MON).toLocaleString("en-US", { style: "currency", currency: "USD" });

/** "3.50" MON-decimal string (from the POS link) → wei */
export function parseMon(s: string): bigint {
  const [w, f = ""] = s.split(".");
  return BigInt(w || "0") * 10n ** 18n + BigInt((f + "0".repeat(18)).slice(0, 18) || "0");
}

export const topicFor = (addr: Address) => pad(addr.toLowerCase() as Hex, { size: 32 });
