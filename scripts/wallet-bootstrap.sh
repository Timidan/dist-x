#!/usr/bin/env bash
set -euo pipefail

# Bootstrap a funded distributor account in the LEZ wallet, print Public/<id>
# on stdout. NOT for token-program definition/supply accounts — those must
# remain uninitialized for the token program to claim them.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ENV_FILE="${DISTRIBUTIONX_ENV_FILE:-${ROOT}/.env.local}"
if [[ -r "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
fi

LEZ_REPO="${DISTRIBUTIONX_LEZ_REPO:-${ROOT}/.scaffold/cache/repos/lez/35d8df0d031315219f94d1546ceb862b0e5b208f}"
WALLET_BIN="${LEZ_REPO}/target/release/wallet"
RPC_URL="${LEZ_RPC_URL:-http://127.0.0.1:3040}"

if [[ ! -x "${WALLET_BIN}" ]]; then
  echo "E_DISTRIBUTIONX_LOCAL_WALLET_MISSING: ${WALLET_BIN}" >&2
  echo "  run 'set -a; source .env.local; set +a; lgs setup' to build the LEZ wallet" >&2
  exit 2
fi

is_localnet() {
  # Strict regex match to avoid `http://localhost.evil` slipping past the
  # bare-glob form.
  [[ "${RPC_URL}" =~ ^http://(127\.0\.0\.1|localhost|\[::1\])(:[0-9]+)?(/.*)?$ ]]
}

default_wallet_home() {
  if [[ -d "${ROOT}/.scaffold/wallet" ]]; then
    printf '%s\n' "${ROOT}/.scaffold/wallet"
  else
    printf '%s\n' "${HOME}/.nssa/wallet"
  fi
}

export NSSA_WALLET_HOME_DIR="${NSSA_WALLET_HOME_DIR:-$(default_wallet_home)}"
mkdir -p "${NSSA_WALLET_HOME_DIR}"

pin_sequencer() {
  if ! "${WALLET_BIN}" config set sequencer_addr "${RPC_URL}" >&2; then
    echo "E_DISTRIBUTIONX_WALLET_CONFIG_SET_FAILED: 'wallet config set sequencer_addr ${RPC_URL}' failed" >&2
    exit 1
  fi
}

deployer_key_present() {
  local id_full="${1:-}"
  [[ -z "${id_full}" ]] && return 1
  [[ -f "${NSSA_WALLET_HOME_DIR}/storage.json" ]] || return 1
  "${WALLET_BIN}" account ls 2>/dev/null | grep -qF -- "${id_full}"
}

account_balance() {
  local account_id="$1"
  "${WALLET_BIN}" account get --account-id "${account_id}" 2>/dev/null \
    | grep -oE '"balance":[0-9]+' | head -n1 | grep -oE '[0-9]+' || echo "0"
}

if [[ -n "${LEZ_DEPLOYER_WALLET:-}" ]]; then
  if deployer_key_present "${LEZ_DEPLOYER_WALLET}"; then
    if is_localnet; then
      balance="$(account_balance "${LEZ_DEPLOYER_WALLET}")"
      min_bal="${DISTRIBUTIONX_BOOTSTRAP_MIN_BALANCE:-1}"
      if (( balance >= min_bal )); then
        echo "LEZ_DEPLOYER_WALLET=${LEZ_DEPLOYER_WALLET} (key present in ${NSSA_WALLET_HOME_DIR}, balance=${balance})" >&2
        pin_sequencer
        echo "${LEZ_DEPLOYER_WALLET}"
        exit 0
      fi
      echo "warning: LEZ_DEPLOYER_WALLET=${LEZ_DEPLOYER_WALLET} has balance=${balance}, below the ${min_bal} threshold; looking for another funded localnet account" >&2
      unset LEZ_DEPLOYER_WALLET
    else
      echo "LEZ_DEPLOYER_WALLET=${LEZ_DEPLOYER_WALLET} (already set, key present in ${NSSA_WALLET_HOME_DIR})" >&2
      pin_sequencer
      echo "${LEZ_DEPLOYER_WALLET}"
      exit 0
    fi
  else
    echo "warning: LEZ_DEPLOYER_WALLET=${LEZ_DEPLOYER_WALLET} has no signing key under ${NSSA_WALLET_HOME_DIR}; bootstrapping a fresh account" >&2
    unset LEZ_DEPLOYER_WALLET
  fi
fi

# Localnet: prefer the highest-balance preconfigured pre-funded public.
# Avoids the "fresh account, zero balance" failure mode on a stale sequencer.
if is_localnet && [[ -f "${NSSA_WALLET_HOME_DIR}/storage.json" ]]; then
  best_acct=""
  best_balance=0
  while read -r acct; do
    [[ -z "${acct}" ]] && continue
    balance="$(account_balance "${acct}")"
    if (( balance > best_balance )); then
      best_balance="${balance}"
      best_acct="${acct}"
    fi
  done < <("${WALLET_BIN}" account ls 2>/dev/null | awk '/^Preconfigured Public\// { print $2 }')

  min_bal="${DISTRIBUTIONX_BOOTSTRAP_MIN_BALANCE:-1}"
  if [[ -n "${best_acct}" && "${best_balance}" -ge "${min_bal}" ]]; then
    echo "using preconfigured ${best_acct} as distributor (balance=${best_balance})" >&2
    pin_sequencer
    echo "${best_acct}"
    exit 0
  fi
  if [[ -n "${best_acct}" ]]; then
    echo "warning: best preconfigured public ${best_acct} has balance=${best_balance}, below the ${min_bal} threshold." >&2
    echo "  the standalone sequencer's preconfigured accounts may be exhausted from prior runs." >&2
    echo "  to reset balances, restart clean: 'bash scripts/standalone-sequencer.sh restart --clean'" >&2
  else
    echo "warning: no preconfigured public account found in wallet storage" >&2
  fi
  # In evidence mode, fail fast rather than wasting an external distributor's
  # time on a run that will silently break at fund/claim.
  if [[ "${DISTRIBUTIONX_BOOTSTRAP_EVIDENCE_MODE:-0}" == "1" ]]; then
    echo "E_DISTRIBUTIONX_BOOTSTRAP_EXHAUSTED_LOCALNET: refusing to fall back to an unfunded account in evidence mode" >&2
    exit 2
  fi
  echo "  falling back to creating a fresh (unfunded) account; subsequent fund/claim transactions WILL fail without a top-up." >&2
fi

# Create a new public account. If storage.json doesn't yet exist, the wallet binary
# will prompt for a password on stdin. That's expected for first-time bootstrap.
new_account_output="$("${WALLET_BIN}" account new public)"
new_account_id="$(printf '%s\n' "${new_account_output}" | sed -n 's/.*account_id \([^ ]*\).*/\1/p' | head -n1)"
if [[ -z "${new_account_id}" ]]; then
  echo "E_DISTRIBUTIONX_ACCOUNT_PARSE_FAILED" >&2
  echo "${new_account_output}" >&2
  exit 1
fi
echo "created ${new_account_id}" >&2

# Pin the wallet's sequencer to LEZ_RPC_URL so future invocations match the adapter.
pin_sequencer

# Initialize the public-distributor account under the authenticated-transfer program
# so it can receive transfers. NOT for token-program definition/supply accounts.
"${WALLET_BIN}" auth-transfer init --account-id "${new_account_id}" >&2

# Fund the new account so it can pay for subsequent operations.
LOCALNET_FUND_AMOUNT="${DISTRIBUTIONX_BOOTSTRAP_FUND_AMOUNT:-10000000}"
if ! is_localnet; then
  echo "claiming testnet faucet funds for ${new_account_id}" >&2
  "${WALLET_BIN}" pinata claim --to "${new_account_id}" >&2
else
  # Localnet has no faucet — top up from a preconfigured pre-funded public.
  funder="$("${WALLET_BIN}" account ls 2>/dev/null \
    | awk '/^Preconfigured Public\// { print $2; exit }' \
    | head -n1 || true)"
  if [[ -z "${funder}" ]]; then
    echo "warning: localnet (${RPC_URL}) has no preconfigured public account in this wallet; ${new_account_id} is unfunded — fund it manually before submitting transactions" >&2
  else
    echo "auto-funding ${new_account_id} with ${LOCALNET_FUND_AMOUNT} units from ${funder}" >&2
    if ! "${WALLET_BIN}" auth-transfer send --from "${funder}" --to "${new_account_id}" --amount "${LOCALNET_FUND_AMOUNT}" >&2; then
      echo "warning: auth-transfer from ${funder} → ${new_account_id} failed; the new account is unfunded" >&2
    fi
  fi
fi

echo "${new_account_id}"
