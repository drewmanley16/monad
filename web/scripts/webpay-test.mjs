// Mirrors src/app/pay/page.tsx: new browser wallet → faucet → pay the invoice via MonadPay.
// Usage: node scripts/webpay-test.mjs "<web checkout URL from the POS QR>"
import { createPublicClient, createWalletClient, defineChain, encodeFunctionData, http, parseAbi } from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";

const q = new URL(process.argv[2]).searchParams;
const chain = defineChain({
  id: 10143, name: "Monad Testnet", nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
  rpcUrls: { default: { http: ["https://testnet-rpc.monad.xyz"] } },
});
const pub = createPublicClient({ chain, transport: http() });
const acct = privateKeyToAccount(generatePrivateKey());
console.log("new browser wallet", acct.address);

let t = Date.now();
const r = await fetch("https://tapnad.vercel.app/api/faucet", {
  method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ address: acct.address }),
});
console.log("faucet", r.status, JSON.stringify(await r.json()));
let bal = 0n;
for (let i = 0; i < 15 && bal === 0n; i++) { await new Promise((res) => setTimeout(res, 500)); bal = await pub.getBalance({ address: acct.address }); }
console.log(`balance $${Number(bal) / 1e16} after ${Date.now() - t} ms`);
await new Promise((res) => setTimeout(res, Number(process.env.SETTLE_MS ?? 0)));

const [w, f = ""] = q.get("amt").split(".");
const amt = BigInt(w) * 10n ** 18n + BigInt((f + "0".repeat(18)).slice(0, 18));
const abi = parseAbi(["function pay(address merchant, bytes32 invoiceId, string memo) payable"]);
const data = encodeFunctionData({ abi, functionName: "pay", args: [q.get("to"), q.get("inv"), q.get("memo")] });
const to = "0xF825f70E27b7f65bB44475FB4530b7c09245F128";
const gas = await pub.estimateGas({ account: acct.address, to, value: amt, data });
const wallet = createWalletClient({ account: acct, chain, transport: http() });
t = Date.now();
const hash = await wallet.sendTransaction({ to, value: amt, data, gas: gas + gas / 10n });
const rc = await pub.waitForTransactionReceipt({ hash });
console.log(`paid $${Number(amt) / 1e16} tx ${hash} status ${rc.status} in ${Date.now() - t} ms`);
