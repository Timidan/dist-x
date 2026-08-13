#!/usr/bin/env bash
set -euo pipefail

# Bootstrap the two public fixture accounts owned by LEZ v0.2.4's standalone
# genesis. This script is deliberately localnet-only; public testnet runs must
# use fresh, private wallet material instead of reproducible fixture keys.

umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEZ_COMMIT=""

ENV_FILE="${DISTRIBUTIONX_ENV_FILE:-${ROOT}/.env.local}"
if [[ -r "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
fi

LEZ_REPO="${DISTRIBUTIONX_LEZ_REPO:-${ROOT}/.scaffold/cache/repos/lez/v0.2.4}"
WALLET_BIN="${LEZ_WALLET_BIN:-${ROOT}/target/lez-v0.2.4-build/release/wallet}"
RPC_URL="${LEZ_RPC_URL:-http://127.0.0.1:3040}"
WALLET_HOME="${LEE_WALLET_HOME_DIR:-${ROOT}/target/lez-v0.2.4-wallet}"
RECEIPT_PATH="${DISTRIBUTIONX_WALLET_BOOTSTRAP_RECEIPT:-${ROOT}/target/lez-v0.2.4-wallet-bootstrap.json}"
JUSTFILE="${LEZ_REPO}/Justfile"
GENESIS_CONFIG="${LEZ_REPO}/lez/sequencer/service/configs/debug/sequencer_config.json"
CLEAN=0

die() { printf 'E_DISTRIBUTIONX_WALLET_BOOTSTRAP: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: scripts/wallet-bootstrap.sh [--clean]

Bootstraps LEZ v0.2.4's two public standalone fixture accounts and prints the
deployer account on stdout. --clean resets only the versioned wallet directory
under this repository's target directory.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean) CLEAN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ "${RPC_URL}" =~ ^http://(127\.0\.0\.1|localhost|\[::1\])(:[0-9]+)?(/.*)?$ ]] \
  || die "fixture bootstrap is localnet-only: ${RPC_URL}"
[[ -x "${WALLET_BIN}" ]] || die "wallet binary missing: ${WALLET_BIN}"
LEZ_COMMIT="$(bash "${ROOT}/scripts/lez-source-guard.sh" "${LEZ_REPO}")" \
  || die "LEZ source validation failed"
[[ -f "${JUSTFILE}" && -f "${GENESIS_CONFIG}" ]] \
  || die "official v0.2.4 fixture sources are missing"

if [[ "${CLEAN}" == "1" ]]; then
  resolved_target="$(realpath -m "${ROOT}/target")"
  resolved_wallet="$(realpath -m "${WALLET_HOME}")"
  [[ "${resolved_wallet}" == "${resolved_target}/"* && "${resolved_wallet}" != "${resolved_target}" ]] \
    || die "refusing --clean outside ${resolved_target}: ${resolved_wallet}"
  rm -rf -- "${WALLET_HOME}"
fi

mkdir -p "${WALLET_HOME}" "$(dirname "${RECEIPT_PATH}")"
chmod 700 "${WALLET_HOME}"

cat > "${WALLET_HOME}/wallet_config.json" <<JSON
{
  "sequencers": [
    {
      "sequencer_addr": "${RPC_URL}"
    }
  ],
  "seq_poll_timeout": "500ms",
  "seq_tx_poll_max_blocks": 30,
  "seq_poll_max_retries": 20,
  "seq_block_poll_max_amount": 100,
  "multi_sequencer_client_config": {
    "distribution_limit": 1,
    "calibration_limit": 1
  }
}
JSON
chmod 600 "${WALLET_HOME}/wallet_config.json"

fixture_output="$(python3 - "${JUSTFILE}" "${GENESIS_CONFIG}" <<'PY'
import json
import re
import sys

justfile, config_path = sys.argv[1:]
text = open(justfile, "r", encoding="utf-8").read()
pattern = re.compile(
    r"wallet account import public --private-key ([0-9a-f]{64})\s+"
    r"just run-wallet vault claim --account-id Public/([1-9A-HJ-NP-Za-km-z]+) --amount ([0-9]+)"
)
rows = pattern.findall(text)
if len(rows) != 2:
    raise SystemExit(f"expected exactly two upstream fixture tuples, found {len(rows)}")
config = json.load(open(config_path, "r", encoding="utf-8"))
genesis = {
    (entry["supply_account"]["account_id"], entry["supply_account"]["balance"])
    for entry in config["genesis"]
    if "supply_account" in entry
}
for private_key, account_id, amount_text in rows:
    amount = int(amount_text)
    if (account_id, amount) not in genesis:
        raise SystemExit(f"fixture {account_id}/{amount} is absent from pinned genesis")
    print(f"{private_key}\tPublic/{account_id}\t{amount}")
PY
)" || die "could not derive official fixture tuples from the pinned checkout"
mapfile -t fixture_rows <<<"${fixture_output}"
[[ "${#fixture_rows[@]}" == "2" ]] || die "expected exactly two validated fixture rows"

fixture_keys=()
fixture_accounts=()
fixture_amounts=()
for row in "${fixture_rows[@]}"; do
  IFS=$'\t' read -r key account amount <<<"${row}"
  [[ "${key}" =~ ^[0-9a-f]{64}$ ]] || die "invalid fixture key shape"
  [[ "${account}" =~ ^Public/[1-9A-HJ-NP-Za-km-z]+$ ]] || die "invalid fixture account shape"
  [[ "${amount}" =~ ^[0-9]+$ ]] || die "invalid fixture amount"
  fixture_keys+=("${key}")
  fixture_accounts+=("${account}")
  fixture_amounts+=("${amount}")
done

wallet_cmd() {
  env LEE_WALLET_HOME_DIR="${WALLET_HOME}" "${WALLET_BIN}" "$@"
}

storage_preexisting=0
[[ -f "${WALLET_HOME}/storage.json" ]] && storage_preexisting=1
if [[ "${storage_preexisting}" == "0" ]]; then
  # The first invocation prints a newly generated mnemonic to stdout. Suppress
  # it completely; this disposable local wallet is never an evidence artifact.
  local_password="${DISTRIBUTIONX_LOCAL_WALLET_PASSWORD:-distributionx-local-only}"
  if ! printf '%s\n' "${local_password}" \
    | wallet_cmd check-health >/dev/null; then
    die "wallet initialization or builtin compatibility check failed"
  fi
  unset local_password
else
  wallet_cmd check-health >/dev/null \
    || die "wallet builtin compatibility check failed"
fi

account_balance() {
  local output json_output
  output="$(wallet_cmd account get --raw --account-id "$1")" \
    || die "could not read account $1"
  json_output="$(sed -n '/^{/,/^}/p' <<<"${output}")"
  jq -er '.balance | numbers' <<<"${json_output}" \
    || die "could not parse balance for $1"
}

account_key_present() {
  local output
  output="$(wallet_cmd account ls 2>/dev/null)" \
    || die "could not list wallet accounts"
  grep -qFx -- "$1" <<<"${output}"
}

if [[ "${storage_preexisting}" == "1" ]]; then
  for account in "${fixture_accounts[@]}"; do
    account_key_present "${account}" \
      || die "existing wallet is not the v0.2.4 fixture wallet; rerun with --clean"
    balance="$(account_balance "${account}")"
    (( balance > 0 )) \
      || die "fixture ${account} is exhausted; restart the sequencer clean and rerun with --clean"
  done
  printf '%s\n' "${fixture_accounts[0]}"
  exit 0
fi

claim_hashes=()
claim_blocks=()
for index in 0 1; do
  wallet_cmd account import public --private-key "${fixture_keys[index]}" >/dev/null \
    || die "fixture account import failed for ${fixture_accounts[index]}"
  account_key_present "${fixture_accounts[index]}" \
    || die "imported key does not match ${fixture_accounts[index]}"

  if ! claim_output="$(wallet_cmd vault claim \
    --account-id "${fixture_accounts[index]}" \
    --amount "${fixture_amounts[index]}" 2>&1)"; then
    printf '%s\n' "${claim_output}" | sed '/^Transaction data is /d' >&2
    die "vault claim failed for ${fixture_accounts[index]}"
  fi
  claim_hash="$(sed -n 's/^Transaction hash is \([0-9a-f]\{64\}\)$/\1/p' <<<"${claim_output}" | tail -1)"
  claim_block="$(sed -n 's/^Transaction is included in block \([0-9][0-9]*\)$/\1/p' <<<"${claim_output}" | tail -1)"
  [[ -n "${claim_hash}" && -n "${claim_block}" ]] \
    || die "wallet did not report claim inclusion for ${fixture_accounts[index]}"
  balance="$(account_balance "${fixture_accounts[index]}")"
  (( balance >= fixture_amounts[index] )) \
    || die "fixture balance ${balance} is below claimed amount ${fixture_amounts[index]}"
  claim_hashes+=("${claim_hash}")
  claim_blocks+=("${claim_block}")
done

jq -n \
  --arg commit "${LEZ_COMMIT}" \
  --arg rpc_url "${RPC_URL}" \
  --arg deployer "${fixture_accounts[0]}" \
  --arg recovery "${fixture_accounts[1]}" \
  --arg first_hash "${claim_hashes[0]}" \
  --argjson first_block "${claim_blocks[0]}" \
  --arg second_hash "${claim_hashes[1]}" \
  --argjson second_block "${claim_blocks[1]}" \
  '{
    status: "WALLET_BOOTSTRAP_OK",
    network: "local-standalone",
    lez_commit: $commit,
    rpc_url: $rpc_url,
    deployer: $deployer,
    recovery: $recovery,
    claims: [
      {account: $deployer, transaction_hash: $first_hash, block_id: $first_block},
      {account: $recovery, transaction_hash: $second_hash, block_id: $second_block}
    ]
  }' > "${RECEIPT_PATH}"
chmod 600 "${RECEIPT_PATH}"

printf 'WALLET_BOOTSTRAP_OK deployer=%s recovery=%s receipt=%s\n' \
  "${fixture_accounts[0]}" "${fixture_accounts[1]}" "${RECEIPT_PATH}" >&2
printf '%s\n' "${fixture_accounts[0]}"
