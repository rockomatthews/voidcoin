#!/bin/sh
set -eu

security_solc="${VOIDCOIN_SOLC_BIN:-$(command -v solc || true)}"

if [ -z "$security_solc" ] || [ ! -x "$security_solc" ]; then
  echo "Solidity 0.8.30 is required. Install it with: solc-select install 0.8.30" >&2
  exit 1
fi

case "$($security_solc --version)" in
  *"Version: 0.8.30"*) ;;
  *)
    echo "VOIDCOIN security analysis requires the exact Solidity 0.8.30 compiler." >&2
    echo "Set VOIDCOIN_SOLC_BIN to the 0.8.30 solc binary and run again." >&2
    exit 1
    ;;
esac

if ! command -v slither >/dev/null 2>&1; then
  echo "Slither 0.11.6 or newer is required." >&2
  exit 1
fi

export FOUNDRY_EVM_VERSION=cancun

slither contracts/src/VOIDLaunch.sol \
  --compile-force-framework solc \
  --solc-solcs-bin "$security_solc" \
  --solc-remaps "@openzeppelin/contracts/=node_modules/@openzeppelin/contracts/" \
  --solc-args "--base-path . --include-path node_modules --evm-version cancun" \
  --filter-paths "node_modules" \
  --exclude timestamp \
  --fail-pedantic
