# Tapnad — tap-to-pay on Monad

An Apple-Wallet-style iPhone wallet that pays merchants on **Monad testnet** with a tap (NFC) or scan (QR),
plus a merchant terminal that confirms the payment **in milliseconds** by streaming Monad's speculative
`monadLogs` (Proposed → Voted → Finalized).

| Part | Path | Stack |
|---|---|---|
| Settlement contract | `contracts/` | Solidity + Foundry — `MonadPay.pay(merchant, invoiceId, memo)` forwards MON, emits `Paid` |
| iPhone wallet | `ios/` | SwiftUI, CoreNFC, VisionKit, Face ID, on-device secp256k1 signing (no wallet SDK) |
| Merchant terminal | `terminal/index.html` | Single HTML page, raw WebSocket to `wss://testnet-rpc.monad.xyz` |

## Run
```bash
# contract (needs a funded key in contracts/.env)
cd contracts && forge test && ./deploy.sh

# terminal
open terminal/index.html

# iOS
cd ios && xcodegen generate && open Tapnad.xcodeproj   # run on a physical iPhone for NFC
```

## Why Monad
- ~300 ms blocks + speculative execution: the terminal turns green on the **Proposed** event, before
  finality — the same UX as a card network's authorization, with finality ~1 s later.
- `monadLogs` delivers commit-state updates per block; the UI shows each stage with live timings.
