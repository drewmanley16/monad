#!/usr/bin/env bash
# Deploys MonadPay to Monad testnet and wires the address into the app + terminal.
set -euo pipefail
cd "$(dirname "$0")"
source .env
ADDR=$(forge create src/MonadPay.sol:MonadPay --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["deployedTo"])')
echo "MonadPay deployed: $ADDR"
sed -i '' -E "s/static let monadPay = \"0x[0-9a-fA-F]{40}\"/static let monadPay = \"$ADDR\"/" ../ios/Tapnad/Eth/MonadRPC.swift
sed -i '' -E "s/const MONADPAY = \"0x[0-9a-fA-F]{40}\"/const MONADPAY = \"$ADDR\"/" ../terminal/index.html
echo "$ADDR" > ../DEPLOYED_ADDRESS
