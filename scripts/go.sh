#!/usr/bin/env bash
# Wait for deployer funds → deploy MonadPay → rebuild + relaunch both apps → fund the simulator wallet.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/contracts/.env"
SIM=${SIM:-789F9BC5-B23D-43C8-85AD-C262C80A10FC}

until [ "$(cast balance "$DEPLOYER" --rpc-url "$RPC_URL")" != "0" ]; do sleep 4; done
echo "deployer funded: $(cast balance "$DEPLOYER" --ether --rpc-url "$RPC_URL") MON"

if grep -q 'monadPay = "0x0000000000000000000000000000000000000000"' "$ROOT/apps/Shared/Core.swift"; then
  "$ROOT/contracts/deploy.sh"
fi

cd "$ROOT/apps"
xcodebuild -project Tapnad.xcodeproj -scheme Wallet -destination 'generic/platform=iOS Simulator' -derivedDataPath build -quiet build
xcodebuild -project Tapnad.xcodeproj -scheme POS -destination 'platform=macOS' -derivedDataPath build -quiet build
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/Tapnad.app
xcrun simctl terminate "$SIM" com.drewmanley.tapnad.wallet 2>/dev/null || true
xcrun simctl launch "$SIM" com.drewmanley.tapnad.wallet >/dev/null
pkill -x "Tapnad POS" 2>/dev/null || true; sleep 1
open "build/Build/Products/Debug/Tapnad POS.app"

sleep 2
D=$(xcrun simctl get_app_container "$SIM" com.drewmanley.tapnad.wallet data)
WALLET=$(python3 -c "import plistlib,sys;print(plistlib.load(open(sys.argv[1],'rb'))['tapnad.address'])" "$D/Library/Preferences/com.drewmanley.tapnad.wallet.plist")
BAL=$(cast balance "$DEPLOYER" --rpc-url "$RPC_URL")
# send half of what's left (max 2 MON) to the simulator wallet
AMT=$(python3 -c "print(min($BAL//2, 2*10**18))")
cast send "$WALLET" --value "$AMT" --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" >/dev/null
echo "funded simulator wallet $WALLET with $(cast from-wei "$AMT") MON"
echo "READY"
