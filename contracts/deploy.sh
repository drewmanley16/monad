#!/usr/bin/env bash
# Deploys MonadPay to Monad testnet and wires the address into the app + terminal.
set -euo pipefail
cd "$(dirname "$0")"
source .env
ADDR=$(forge create src/MonadPay.sol:MonadPay --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["deployedTo"])')
echo "MonadPay deployed: $ADDR"
sed -i '' -E "s/static let monadPay = \"0x[0-9a-fA-F]{40}\"/static let monadPay = \"$ADDR\"/" ../apps/Shared/Core.swift
echo "$ADDR" > ../DEPLOYED_ADDRESS
