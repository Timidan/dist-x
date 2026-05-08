#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

usage() {
  cat <<'EOF'
Usage: scripts/e2e.sh <mode>

Modes:
  localnet      Run the full CLI E2E against an already-running local LEZ RPC.
  private-localnet
                Run localnet E2E with the shielded destination packet and private claim tx path.
  ci-localnet   Start a configured standalone sequencer, then run localnet E2E.
  testnet       Run the full CLI E2E against the configured LEZ RPC and submit adapters.
  basecamp      Package/install LGX assets and launch Basecamp with .env.local.
  package       Build the two Basecamp LGX assets under target/lgx/.

The localnet/testnet CLI E2E deploys, initializes, funds, proves with
RISC0_DEV_MODE=0, verifies, claims, rejects a double claim, closes on-chain,
and writes logs under docs/run-logs/e2e/.

Localnet runs use fixtures/reviewer-fast-path by default. Set
DISTRIBUTIONX_USE_REVIEWER_FIXTURE=0 to generate fresh sample keys.
EOF
}

mode="${1:-}"
if [[ -z "${mode}" || "${mode}" == "-h" || "${mode}" == "--help" ]]; then
  usage
  exit 0
fi
shift
PRIVATE_CLAIM="${DISTRIBUTIONX_USE_PRIVATE_CLAIM:-0}"

load_env_file() {
  local env_file="${DISTRIBUTIONX_ENV_FILE:-${ROOT}/.env.local}"
  if [[ -n "${DISTRIBUTIONX_ENV_FILE:-}" && "${env_file}" != /* ]]; then
    env_file="${ROOT}/${env_file}"
  fi
  if [[ -r "${env_file}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${env_file}"
    set +a
  elif [[ -n "${DISTRIBUTIONX_ENV_FILE:-}" ]]; then
    echo "E_DISTRIBUTIONX_ENV_FILE_NOT_FOUND: ${env_file}" >&2
    exit 2
  fi
}

is_local_rpc() {
  local value="$1"
  [[ "${value}" == http://127.0.0.1* ||
     "${value}" == http://localhost* ||
     "${value}" == http://[[]::1[]]* ]]
}

write_ci_summary() {
  local status="$1"
  local message="$2"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "### DistributionX localnet E2E"
      echo
      echo "${status}: ${message}"
    } >> "${GITHUB_STEP_SUMMARY}"
  fi
}

skip_or_fail_ci_localnet() {
  local message="$1"
  if [[ "${DISTRIBUTIONX_LOCALNET_E2E_ALLOW_SKIP:-0}" == "1" ]]; then
    echo "DISTRIBUTIONX_LOCALNET_E2E_SKIPPED: ${message}"
    write_ci_summary "Skipped" "${message}"
    exit 0
  fi
  echo "E_DISTRIBUTIONX_LOCALNET_E2E_NOT_READY: ${message}" >&2
  echo "Set DISTRIBUTIONX_LOCALNET_E2E_ALLOW_SKIP=1 only when CI should report this job as skipped." >&2
  exit 2
}

resolve_executable() {
  local candidate="$1"
  if [[ "${candidate}" == */* ]]; then
    [[ -x "${candidate}" ]] && printf '%s\n' "${candidate}"
  else
    command -v "${candidate}" 2>/dev/null || true
  fi
}

find_sequencer() {
  if [[ -n "${DISTRIBUTIONX_LEZ_SEQUENCER_BIN:-}" ]]; then
    resolve_executable "${DISTRIBUTIONX_LEZ_SEQUENCER_BIN}" || true
    return
  fi

  local candidate
  for candidate in lez-sequencer lez_sequencer logos-lez-sequencer logos_lez_sequencer lez-node lez; do
    if resolve_executable "${candidate}" >/dev/null; then
      resolve_executable "${candidate}"
      return
    fi
  done
}

CI_LOCALNET=0
SEQUENCER_PID=""

cleanup_ci_localnet() {
  if [[ -n "${SEQUENCER_PID}" ]] && kill -0 "${SEQUENCER_PID}" 2>/dev/null; then
    kill "${SEQUENCER_PID}" 2>/dev/null || true
    wait "${SEQUENCER_PID}" 2>/dev/null || true
  fi
  if [[ -n "${DISTRIBUTIONX_LEZ_SEQUENCER_STOP_COMMAND:-}" ]]; then
    bash -c "${DISTRIBUTIONX_LEZ_SEQUENCER_STOP_COMMAND}" >/dev/null 2>&1 || true
  fi
}

setup_ci_localnet() {
  load_env_file

  local sequencer_bin=""
  if [[ -z "${DISTRIBUTIONX_LEZ_SEQUENCER_START_COMMAND:-}" ]]; then
    sequencer_bin="$(find_sequencer)"
    if [[ -z "${sequencer_bin}" ]]; then
      skip_or_fail_ci_localnet "no standalone LEZ sequencer binary found; set DISTRIBUTIONX_LEZ_SEQUENCER_BIN or DISTRIBUTIONX_LEZ_SEQUENCER_START_COMMAND"
    fi
  fi

  [[ -n "${DISTRIBUTIONX_INIT_SUBMIT_COMMAND:-}" ]] || skip_or_fail_ci_localnet "DISTRIBUTIONX_INIT_SUBMIT_COMMAND is required — all transactions must touch the chain"
  [[ -n "${DISTRIBUTIONX_FUND_SUBMIT_COMMAND:-}" ]] || skip_or_fail_ci_localnet "DISTRIBUTIONX_FUND_SUBMIT_COMMAND is required — all transactions must touch the chain"
  [[ -n "${DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND:-}" ]] || skip_or_fail_ci_localnet "DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND is required — all transactions must touch the chain"
  [[ -n "${DISTRIBUTIONX_CLOSE_SUBMIT_COMMAND:-}" ]] || skip_or_fail_ci_localnet "DISTRIBUTIONX_CLOSE_SUBMIT_COMMAND is required — close must touch the chain"

  export LEZ_RPC_URL="${DISTRIBUTIONX_LOCALNET_RPC_URL:-${LEZ_RPC_URL:-http://127.0.0.1:3040}}"
  if ! is_local_rpc "${LEZ_RPC_URL}"; then
    skip_or_fail_ci_localnet "LEZ_RPC_URL must point at a local sequencer for this job, got ${LEZ_RPC_URL}"
  fi

  [[ -n "${LEZ_DEPLOYER_WALLET:-}" ]] || skip_or_fail_ci_localnet "LEZ_DEPLOYER_WALLET must be a funded local wallet account"

  export DISTRIBUTIONX_TOKEN_ID="${DISTRIBUTIONX_TOKEN_ID:-Public/localnet-token}"
  export DISTRIBUTIONX_RECOVERY_ADDRESS="${DISTRIBUTIONX_RECOVERY_ADDRESS:-Public/localnet-recovery}"
  export DISTRIBUTIONX_RELAYER_URL="${DISTRIBUTIONX_RELAYER_URL:-localnet}"
  export DISTRIBUTIONX_STATE_DIR="${DISTRIBUTIONX_STATE_DIR:-${ROOT}/target/distributionx-localnet}"
  export DISTRIBUTIONX_SERIALIZED_LEZ_TX="${DISTRIBUTIONX_SERIALIZED_LEZ_TX:-${DISTRIBUTIONX_STATE_DIR}/claim.tx}"
  export DISTRIBUTIONX_ENV_FILE=/dev/null
  export RISC0_DEV_MODE=0

  local log_dir="${ROOT}/docs/run-logs/ci-e2e"
  mkdir -p "${log_dir}"
  local sequencer_log="${log_dir}/sequencer.log"
  if [[ -n "${DISTRIBUTIONX_LEZ_SEQUENCER_START_COMMAND:-}" ]]; then
    bash -c "${DISTRIBUTIONX_LEZ_SEQUENCER_START_COMMAND}" > "${sequencer_log}" 2>&1 &
  else
    "${sequencer_bin}" ${DISTRIBUTIONX_LEZ_SEQUENCER_ARGS:-} > "${sequencer_log}" 2>&1 &
  fi
  SEQUENCER_PID="$!"
  trap cleanup_ci_localnet EXIT

  echo "Started LEZ sequencer pid=${SEQUENCER_PID} rpc=${LEZ_RPC_URL} log=${sequencer_log}"

  local ready=0
  for _ in $(seq 1 "${DISTRIBUTIONX_LOCALNET_READY_ATTEMPTS:-60}"); do
    local http_code
    http_code="$(curl --max-time 2 -sS -o /dev/null -w '%{http_code}' "${LEZ_RPC_URL}" 2>/dev/null || true)"
    if [[ -n "${http_code}" && "${http_code}" != "000" ]]; then
      ready=1
      break
    fi
    if ! kill -0 "${SEQUENCER_PID}" 2>/dev/null; then
      if [[ -n "${DISTRIBUTIONX_LEZ_SEQUENCER_START_COMMAND:-}" ]]; then
        sleep 1
        continue
      fi
      cat "${sequencer_log}" >&2 || true
      echo "E_LEZ_SEQUENCER_EXITED_BEFORE_READY" >&2
      exit 1
    fi
    sleep 1
  done

  if [[ "${ready}" != "1" ]]; then
    cat "${sequencer_log}" >&2 || true
    echo "E_LEZ_SEQUENCER_NOT_READY: ${LEZ_RPC_URL}" >&2
    exit 1
  fi
}

case "${mode}" in
  localnet)
    load_env_file
    PRIVATE_CLAIM="${DISTRIBUTIONX_USE_PRIVATE_CLAIM:-${PRIVATE_CLAIM}}"
    export LEZ_RPC_URL="${DISTRIBUTIONX_LOCALNET_RPC_URL:-${LEZ_RPC_URL:-http://127.0.0.1:3040}}"
    export DISTRIBUTIONX_RELAYER_URL="${DISTRIBUTIONX_RELAYER_URL:-localnet}"
    export DISTRIBUTIONX_ENV_FILE=/dev/null
    export RISC0_DEV_MODE=0
    if ! is_local_rpc "${LEZ_RPC_URL}"; then
      echo "E_DISTRIBUTIONX_LOCALNET_RPC_REQUIRED: ${LEZ_RPC_URL}" >&2
      exit 2
    fi
    http_code="$(curl --max-time 2 -sS -o /dev/null -w '%{http_code}' "${LEZ_RPC_URL}" 2>/dev/null || true)"
    if [[ -z "${http_code}" || "${http_code}" == "000" ]]; then
      echo "E_DISTRIBUTIONX_LOCALNET_RPC_NOT_READY: ${LEZ_RPC_URL}" >&2
      echo "Start the LEZ sequencer first, or use mode ci-localnet with DISTRIBUTIONX_LEZ_SEQUENCER_START_COMMAND." >&2
      exit 2
    fi
    ;;
  private-localnet)
    load_env_file
    export DISTRIBUTIONX_USE_PRIVATE_CLAIM=1
    PRIVATE_CLAIM=1
    export LEZ_RPC_URL="${DISTRIBUTIONX_LOCALNET_RPC_URL:-${LEZ_RPC_URL:-http://127.0.0.1:3040}}"
    export DISTRIBUTIONX_RELAYER_URL="${DISTRIBUTIONX_RELAYER_URL:-localnet}"
    export DISTRIBUTIONX_ENV_FILE=/dev/null
    export RISC0_DEV_MODE=0
    mode=localnet
    if ! is_local_rpc "${LEZ_RPC_URL}"; then
      echo "E_DISTRIBUTIONX_LOCALNET_RPC_REQUIRED: ${LEZ_RPC_URL}" >&2
      exit 2
    fi
    http_code="$(curl --max-time 2 -sS -o /dev/null -w '%{http_code}' "${LEZ_RPC_URL}" 2>/dev/null || true)"
    if [[ -z "${http_code}" || "${http_code}" == "000" ]]; then
      echo "E_DISTRIBUTIONX_LOCALNET_RPC_NOT_READY: ${LEZ_RPC_URL}" >&2
      echo "Start the LEZ sequencer first." >&2
      exit 2
    fi
    ;;
  testnet)
    export RISC0_DEV_MODE=0
    ;;
  ci-localnet)
    setup_ci_localnet
    CI_LOCALNET=1
    mode=localnet
    ;;
  basecamp)
    exec bash scripts/start-basecamp.sh "$@"
    ;;
  package)
    exec bash scripts/package.sh "$@"
    ;;
  *)
    echo "Unknown mode: ${mode}" >&2
    usage >&2
    exit 2
    ;;
esac

# Proof flow — reached only by localnet and testnet modes.

ENV_FILE="${DISTRIBUTIONX_ENV_FILE:-${ROOT}/.env.local}"
if [[ -n "${DISTRIBUTIONX_ENV_FILE:-}" && "${ENV_FILE}" != /* ]]; then
  ENV_FILE="${ROOT}/${ENV_FILE}"
fi
if [[ -r "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
elif [[ -n "${DISTRIBUTIONX_ENV_FILE:-}" ]]; then
  echo "E_DISTRIBUTIONX_ENV_FILE_NOT_FOUND: ${ENV_FILE}" >&2
  exit 2
fi
PRIVATE_CLAIM="${DISTRIBUTIONX_USE_PRIVATE_CLAIM:-${PRIVATE_CLAIM}}"

LOG_DIR="${ROOT}/docs/run-logs/e2e"
STATE_DIR="${DISTRIBUTIONX_STATE_DIR:-${ROOT}/target/distributionx-testnet}"
mkdir -p "${LOG_DIR}"
rm -f "${LOG_DIR}"/*.log "${LOG_DIR}"/*.json
rm -rf "${STATE_DIR}"
export DISTRIBUTIONX_STATE_DIR="${STATE_DIR}"
export DISTRIBUTIONX_AIRDROP_NAME="${DISTRIBUTIONX_AIRDROP_NAME:-demo-airdrop}"
export DISTRIBUTIONX_FUND_AMOUNT="${DISTRIBUTIONX_FUND_AMOUNT:-3000}"
export DISTRIBUTIONX_EXPIRY_UNIX="${DISTRIBUTIONX_EXPIRY_UNIX:-1893456000}"

default_wallet_home() {
  if [[ -d "${ROOT}/.scaffold/wallet" ]]; then
    printf '%s\n' "${ROOT}/.scaffold/wallet"
  else
    printf '%s\n' "${HOME}/.nssa/wallet"
  fi
}

if [[ "${mode}" == "localnet" ]]; then
  export NSSA_WALLET_HOME_DIR="${NSSA_WALLET_HOME_DIR:-$(default_wallet_home)}"
  export DISTRIBUTIONX_BOOTSTRAP_EVIDENCE_MODE="${DISTRIBUTIONX_BOOTSTRAP_EVIDENCE_MODE:-1}"
  LEZ_DEPLOYER_WALLET="$(bash "${ROOT}/scripts/wallet-bootstrap.sh")"
  export LEZ_DEPLOYER_WALLET
  if [[ -z "${DISTRIBUTIONX_RECOVERY_ADDRESS:-}" ]]; then
    LOCAL_WALLET_BIN="${DISTRIBUTIONX_LEZ_REPO:-${ROOT}/.scaffold/cache/repos/lez/35d8df0d031315219f94d1546ceb862b0e5b208f}/target/release/wallet"
    RECOVERY_CANDIDATE=""
    if [[ -x "${LOCAL_WALLET_BIN}" ]]; then
      RECOVERY_CANDIDATE="$("${LOCAL_WALLET_BIN}" account ls 2>/dev/null \
        | awk '/^Preconfigured Public\// { print $2 }' \
        | grep -vFx -- "${LEZ_DEPLOYER_WALLET}" \
        | head -n 1 || true)"
    fi
    if [[ -z "${RECOVERY_CANDIDATE}" ]]; then
      echo "E_DISTRIBUTIONX_LOCALNET_RECOVERY_ACCOUNT_MISSING: need an initialized public account distinct from ${LEZ_DEPLOYER_WALLET}" >&2
      exit 2
    fi
    export DISTRIBUTIONX_RECOVERY_ADDRESS="${RECOVERY_CANDIDATE}"
  fi
fi

if [[ -n "${DISTRIBUTIONX_SERIALIZED_LEZ_TX_BASE64:-}" ]]; then
  if [[ -z "${DISTRIBUTIONX_SERIALIZED_LEZ_TX:-}" ]]; then
    echo "E_DISTRIBUTIONX_SERIALIZED_LEZ_TX_REQUIRED_FOR_BASE64" >&2
    exit 2
  fi
  mkdir -p "$(dirname "${DISTRIBUTIONX_SERIALIZED_LEZ_TX}")"
  if ! printf '%s' "${DISTRIBUTIONX_SERIALIZED_LEZ_TX_BASE64}" | base64 --decode > "${DISTRIBUTIONX_SERIALIZED_LEZ_TX}"; then
    echo "E_DISTRIBUTIONX_SERIALIZED_LEZ_TX_BASE64_INVALID" >&2
    exit 2
  fi
fi

missing_env=()

require_env() {
  local name="$1"
  local hint="${2:-}"
  if [[ -z "${!name:-}" ]]; then
    if [[ -n "${hint}" ]]; then
      missing_env+=("${name} (${hint})")
    else
      missing_env+=("${name}")
    fi
  fi
}

require_env LEZ_RPC_URL
require_env LEZ_DEPLOYER_WALLET
require_env DISTRIBUTIONX_RELAYER_URL
require_env DISTRIBUTIONX_SERIALIZED_LEZ_TX

require_env DISTRIBUTIONX_INIT_SUBMIT_COMMAND "must submit real on-chain init tx"
require_env DISTRIBUTIONX_FUND_SUBMIT_COMMAND "must submit real on-chain fund tx"
require_env DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND "must submit real on-chain claim tx"
require_env DISTRIBUTIONX_CLOSE_SUBMIT_COMMAND "must submit real on-chain close tx"

if (( ${#missing_env[@]} > 0 )); then
  echo "E_DISTRIBUTIONX_PREFLIGHT_FAILED" >&2
  echo "Missing or invalid environment:" >&2
  printf '  - %s\n' "${missing_env[@]}" >&2
  echo "Set these in the shell, ${ROOT}/.env.local, or DISTRIBUTIONX_ENV_FILE." >&2
  echo "Use ${ROOT}/.env.example as the template." >&2
  exit 2
fi

if [[ -z "${DISTRIBUTIONX_CLI:-}" ]]; then
  case "${DISTRIBUTIONX_CARGO_PROFILE:-release}" in
    release)
      cargo build -p distributionx-cli --release
      export DISTRIBUTIONX_CLI="${ROOT}/target/release/distributionx-cli"
      ;;
    debug)
      cargo build -p distributionx-cli
      export DISTRIBUTIONX_CLI="${ROOT}/target/debug/distributionx-cli"
      ;;
    *)
      echo "E_DISTRIBUTIONX_CARGO_PROFILE_INVALID: ${DISTRIBUTIONX_CARGO_PROFILE}" >&2
      echo "Use debug or release." >&2
      exit 2
      ;;
  esac
fi

if [[ ! -x "${DISTRIBUTIONX_CLI}" ]]; then
  echo "E_DISTRIBUTIONX_CLI_NOT_EXECUTABLE: ${DISTRIBUTIONX_CLI}" >&2
  exit 2
fi

cli() {
  "${DISTRIBUTIONX_CLI}" "$@"
}

run_step() {
  local name="$1"
  shift
  local log="${LOG_DIR}/${name}.log"
  "$@" >"${log}" 2>&1
  cat "${log}"
}

run_step_with_notice() {
  local name="$1"
  local notice="$2"
  shift 2
  local log="${LOG_DIR}/${name}.log"
  {
    echo "${notice}"
    "$@"
  } >"${log}" 2>&1
  cat "${log}"
}

assert_marker() {
  local name="$1"
  local marker="$2"
  local log="${LOG_DIR}/${name}.log"
  if ! grep -q "${marker}" "${log}"; then
    echo "missing marker ${marker} in ${log}" >&2
    exit 1
  fi
}

json_string_field() {
  local field="$1"
  sed -n "s/.*\"${field}\":\"\\([^\"]*\\)\".*/\\1/p" | tail -n 1
}

claim_destination_args() {
  if [[ -n "${DISTRIBUTIONX_CLAIM_DESTINATION_COMMITMENT:-}" ]]; then
    printf '%s\n' --claim-destination-commitment "${DISTRIBUTIONX_CLAIM_DESTINATION_COMMITMENT}"
  else
    printf '%s\n' --destination-packet "${STATE_DIR}/shielded_destination.json"
  fi
}

echo "DistributionX E2E"
echo "RISC0_DEV_MODE=${RISC0_DEV_MODE}"
echo "DISTRIBUTIONX_CLI=${DISTRIBUTIONX_CLI}"

USE_REVIEWER_FIXTURE="${DISTRIBUTIONX_USE_REVIEWER_FIXTURE:-}"
if [[ -z "${USE_REVIEWER_FIXTURE}" ]]; then
  if [[ "${mode}" == "localnet" ]]; then
    USE_REVIEWER_FIXTURE=1
  else
    USE_REVIEWER_FIXTURE=0
  fi
fi

if [[ "${USE_REVIEWER_FIXTURE}" == "1" ]]; then
  run_step sample env DISTRIBUTIONX_STATE_DIR="${STATE_DIR}" "${ROOT}/scripts/install-reviewer-fixture.sh"
else
  run_step sample cli sample-fixture --out-dir "${STATE_DIR}"
fi
assert_marker sample "SAMPLE_FIXTURE_OK"

if [[ -z "${DISTRIBUTIONX_TOKEN_ID:-}" ]]; then
  DISTRIBUTIONX_TOKEN_ID="$(cli token-id --name "${DISTRIBUTIONX_AIRDROP_NAME}-token" | json_string_field token_id)"
  export DISTRIBUTIONX_TOKEN_ID
fi

if [[ -z "${DISTRIBUTIONX_RECOVERY_ADDRESS:-}" ]]; then
  DISTRIBUTIONX_RECOVERY_ADDRESS="$(json_string_field admin_account < "${LOG_DIR}/sample.log")"
  export DISTRIBUTIONX_RECOVERY_ADDRESS
fi

if [[ -z "${DISTRIBUTIONX_TOKEN_ID:-}" || -z "${DISTRIBUTIONX_RECOVERY_ADDRESS:-}" ]]; then
  echo "E_DISTRIBUTIONX_SAMPLE_DERIVATION_FAILED" >&2
  exit 2
fi

if [[ "${mode}" == "localnet" && "${PRIVATE_CLAIM}" != "1" && -z "${DISTRIBUTIONX_CLAIM_DESTINATION_COMMITMENT:-}" ]]; then
  # Public LEZ claims can only credit an already-initialized public account.
  # The generated shielded fixture is for private claims; use the funded
  # distributor account as the localnet public recipient unless overridden.
  export DISTRIBUTIONX_CLAIM_DESTINATION_COMMITMENT="${LEZ_DEPLOYER_WALLET}"
fi

run_step deploy scripts/deploy.sh "--${mode}"
assert_marker deploy "DEPLOY_${mode^^}_OK"

run_step init cli init \
  --csv "${STATE_DIR}/eligible.csv" \
  --distributor "${LEZ_DEPLOYER_WALLET}" \
  --token "${DISTRIBUTIONX_TOKEN_ID}" \
  --rpc "${LEZ_RPC_URL}" \
  --expiry "${DISTRIBUTIONX_EXPIRY_UNIX}" \
  --recovery "${DISTRIBUTIONX_RECOVERY_ADDRESS}"
assert_marker init "INIT_OK"

run_step fund cli fund --airdrop "${DISTRIBUTIONX_AIRDROP_NAME}" --amount "${DISTRIBUTIONX_FUND_AMOUNT}"
assert_marker fund "FUND_OK"

mapfile -t CLAIM_DESTINATION_ARGS < <(claim_destination_args)
run_step_with_notice prove "RISC0_DEV_MODE=${RISC0_DEV_MODE}" cli prove \
  --airdrop "${DISTRIBUTIONX_AIRDROP_NAME}" \
  --bundle "${STATE_DIR}/bundle.json" \
  --wallet "${STATE_DIR}/wallet.seed" \
  "${CLAIM_DESTINATION_ARGS[@]}"
assert_marker prove "RISC0_DEV_MODE=0"
assert_marker prove "PROVE_LOCAL_OK"
assert_marker prove "claim_destination_commitment"
assert_marker prove '"risc0_real_proof":"OK"'

if [[ "${PRIVATE_CLAIM}" == "1" ]]; then
  if ! jq -e '.private_claim != null and .recipient_npk != null and .recipient_vpk != null' "${DISTRIBUTIONX_SERIALIZED_LEZ_TX}" >/dev/null; then
    echo "private-localnet did not produce a private claim transaction" >&2
    exit 1
  fi
fi

if grep -q "claim_address" "${STATE_DIR}/proof.json"; then
  echo "proof journal still contains claim_address" >&2
  exit 1
fi

run_step verify-before-claim cli verify \
  --airdrop "${DISTRIBUTIONX_AIRDROP_NAME}" \
  --proof "${STATE_DIR}/proof.json"
assert_marker verify-before-claim "VERIFY_OK"
assert_marker verify-before-claim '"risc0_receipt_verify":"verified"'

run_step claim cli claim \
  --airdrop "${DISTRIBUTIONX_AIRDROP_NAME}" \
  --proof "${STATE_DIR}/proof.json" \
  --relayer "${DISTRIBUTIONX_RELAYER_URL}" \
  --serialized-lez-tx "${DISTRIBUTIONX_SERIALIZED_LEZ_TX}"
assert_marker claim "CLAIM_OK"

if [[ -x "${ROOT}/scripts/extract-cu.sh" ]]; then
  bash "${ROOT}/scripts/extract-cu.sh" >/dev/null
fi

if cli claim --airdrop "${DISTRIBUTIONX_AIRDROP_NAME}" --proof "${STATE_DIR}/proof.json" --relayer "${DISTRIBUTIONX_RELAYER_URL}" --serialized-lez-tx "${DISTRIBUTIONX_SERIALIZED_LEZ_TX}" >"${LOG_DIR}/double-claim.log" 2>&1; then
  echo "double claim unexpectedly succeeded" >&2
  exit 1
fi
cat "${LOG_DIR}/double-claim.log"
assert_marker double-claim "E_ALREADY_CLAIMED"

run_step close cli close --airdrop "${DISTRIBUTIONX_AIRDROP_NAME}"
assert_marker close "CLOSE_OK"

echo "DISTRIBUTIONX_E2E_PASS logs=${LOG_DIR}"
if [[ "${CI_LOCALNET}" == "1" ]]; then
  echo "DISTRIBUTIONX_LOCALNET_E2E_PASS rpc=${LEZ_RPC_URL} logs=${LOG_DIR}"
  write_ci_summary "Passed" "real local sequencer demo completed against ${LEZ_RPC_URL}"
fi
