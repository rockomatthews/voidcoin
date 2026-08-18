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
security_tmp_dir="$(mktemp -d)"
security_index=0
trap 'rm -f "$security_tmp_dir"/*.json; rmdir "$security_tmp_dir"' EXIT

for security_target in \
  contracts/src/VOIDLaunch.sol \
  contracts/src/VOIDUniswapV3Migration.sol \
  contracts/src/VOIDGraduationExecutor.sol \
  contracts/src/VOIDPositionLocker.sol \
  contracts/src/VOIDCoinV2.sol \
  contracts/src/VOIDV2Launch.sol \
  contracts/src/VOIDV2BuyRouter.sol; do
  security_index=$((security_index + 1))
  security_report="$security_tmp_dir/slither-$security_index.json"
  if ! slither "$security_target" \
      --compile-force-framework solc \
      --solc-solcs-bin "$security_solc" \
      --solc-remaps "@openzeppelin/contracts/=node_modules/@openzeppelin/contracts/" \
      --solc-args "--base-path . --include-path node_modules --evm-version cancun" \
      --filter-paths "node_modules" \
      --exclude timestamp \
      --json "$security_report" \
      --fail-none; then
    exit 1
  fi
  if ! jq -e '(.results.detectors // []) | length == 0' "$security_report" >/dev/null; then
    echo "Slither findings detected in $security_target" >&2
    exit 1
  fi
done
