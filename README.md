# Tapnad — tap-to-pay on Monad

Native Swift. An Apple-Wallet-style **iPhone wallet** taps a **Mac point-of-sale** to pay in MON on Monad testnet.
The register shows **Approved** the moment the payment is *Proposed* (~300 ms blocks), then walks through
Voted → Finalized live via Monad's `monadLogs` commit-state stream.

**▶ [Watch the launch video](https://github.com/drewmanley16/monad/releases/download/launch-video/tapnad-launch-16x9.mp4)** (39 s · [portrait cut](https://github.com/drewmanley16/monad/releases/download/launch-video/tapnad-launch-4x5.mp4) · [release](https://github.com/drewmanley16/monad/releases/tag/launch-video))

| Part | Path | Notes |
|---|---|---|
| Wallet (iOS 18+) | `apps/Wallet` | SwiftUI, on-device secp256k1 signing (no wallet SDK), Face ID, Keychain |
| POS (macOS 15+) | `apps/POS` | Catalog + cart, charge screen, Activity dashboard (Swift Charts), live blocks |
| Shared | `apps/Shared` | Monad RPC + WebSocket stream, MonadPay ABI, payment request, design system |
| Contract | `contracts/` | `MonadPay.pay(merchant, invoiceId, memo)` — forwards MON, emits `Paid` |

**Tap transport:** the POS advertises the active charge over **Bluetooth LE** (a real iPhone triggers only when
held against the Mac, by RSSI) and **Bonjour** (iOS Simulator on the same Mac).

## Run
```bash
./scripts/go.sh   # waits for deployer funds → deploys → builds & launches both apps → funds the sim wallet
```
Manual: `cd apps && xcodegen generate && open Tapnad.xcodeproj` (schemes: Wallet, POS).
