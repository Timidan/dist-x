#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

usage() {
  cat <<'EOF'
Usage: scripts/e2e.sh <mode>

Modes:
  localnet      Run the full shielded CLI E2E against an already-running local LEZ RPC.
  private-localnet
                Backward-compatible alias for localnet.
  ci-localnet   Build/start pinned LEZ v0.2.4 standalone, then run localnet E2E.
  testnet       Run the full CLI E2E against the configured LEZ RPC and submit adapters.
  basecamp      Package/install LGX assets and launch Basecamp with .env.local.
  package       Build the two Basecamp LGX assets under target/lgx/.

The localnet/testnet CLI E2E deploys, initializes, funds, proves with
RISC0_DEV_MODE=0, verifies, claims, and rejects a double claim. Localnet closes
on-chain; testnet leaves the distribution open unless
DISTRIBUTIONX_CLOSE_AFTER_E2E=1. Logs are written under docs/run-logs/e2e/.

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

case "${mode}" in
  localnet|private-localnet|ci-localnet|testnet)
    bash "${ROOT}/scripts/docker-preflight.sh"
    DISTRIBUTIONX_REAL_DOCKER="$(type -P docker)"
    if [[ -z "${DISTRIBUTIONX_REAL_DOCKER}" || "${DISTRIBUTIONX_REAL_DOCKER}" != /* ]]; then
      echo "E_DISTRIBUTIONX_REAL_DOCKER_INVALID" >&2
      exit 2
    fi
    export DISTRIBUTIONX_REAL_DOCKER
    export PATH="${ROOT}/scripts/risc0-docker-bin:${PATH}"
    ;;
esac

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

default_local_submit_hooks() {
  export DISTRIBUTIONX_INIT_SUBMIT_COMMAND="${DISTRIBUTIONX_INIT_SUBMIT_COMMAND:-bash ${ROOT}/scripts/local-submit.sh init}"
  export DISTRIBUTIONX_FUND_SUBMIT_COMMAND="${DISTRIBUTIONX_FUND_SUBMIT_COMMAND:-bash ${ROOT}/scripts/local-submit.sh fund}"
  export DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND="${DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND:-bash ${ROOT}/scripts/local-submit.sh claim}"
  export DISTRIBUTIONX_CLOSE_SUBMIT_COMMAND="${DISTRIBUTIONX_CLOSE_SUBMIT_COMMAND:-bash ${ROOT}/scripts/local-submit.sh close}"
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

CI_LOCALNET=0
CI_OWNS_SEQUENCER=0

cleanup_ci_localnet() {
  local status=$?
  if [[ "${CI_OWNS_SEQUENCER}" == "1" ]]; then
    if ! bash "${ROOT}/scripts/standalone-sequencer.sh" stop; then
      status=1
    fi
    local sequencer_log="/tmp/distributionx-standalone-sequencer-${UID:-$(id -u)}.log"
    if [[ -n "${LOG_DIR:-}" && -f "${sequencer_log}" ]]; then
      mkdir -p "${LOG_DIR}"
      cp -- "${sequencer_log}" "${LOG_DIR}/sequencer.log"
    fi
  fi
  trap - EXIT
  exit "${status}"
}

setup_ci_localnet() {
  # Canonical CI is secret-free and does not inherit a developer's possibly
  # stale rc5 .env.local. Every runtime path is version-scoped below.
  export DISTRIBUTIONX_ENV_FILE=/dev/null
  export DISTRIBUTIONX_LEZ_REPO="${DISTRIBUTIONX_LEZ_REPO:-${ROOT}/.scaffold/cache/repos/lez/v0.2.4}"
  export LEZ_WALLET_BIN="${LEZ_WALLET_BIN:-${ROOT}/target/lez-v0.2.4-build/release/wallet}"
  export LEE_WALLET_HOME_DIR="${ROOT}/target/lez-v0.2.4-wallet"
  export LEZ_RPC_URL="${DISTRIBUTIONX_LOCALNET_RPC_URL:-http://127.0.0.1:3040}"
  if ! is_local_rpc "${LEZ_RPC_URL}"; then
    echo "E_DISTRIBUTIONX_LOCALNET_RPC_REQUIRED: ${LEZ_RPC_URL}" >&2
    exit 2
  fi
  default_local_submit_hooks

  export DISTRIBUTIONX_RELAYER_URL="${DISTRIBUTIONX_RELAYER_URL:-localnet}"
  export DISTRIBUTIONX_STATE_DIR="${DISTRIBUTIONX_STATE_DIR:-${ROOT}/target/distributionx-localnet}"
  export DISTRIBUTIONX_SERIALIZED_LEZ_TX="${DISTRIBUTIONX_SERIALIZED_LEZ_TX:-${DISTRIBUTIONX_STATE_DIR}/claim.tx}"
  export RISC0_DEV_MODE=0
  CI_OWNS_SEQUENCER=1
  trap cleanup_ci_localnet EXIT
  bash "${ROOT}/scripts/standalone-sequencer.sh" restart --clean
  bash "${ROOT}/scripts/lez-fingerprint.sh" --rpc "${LEZ_RPC_URL}" \
    --expected-channel "$(printf '01%.0s' {1..32})" >/dev/null
}

case "${mode}" in
  localnet)
    load_env_file
    export LEZ_RPC_URL="${DISTRIBUTIONX_LOCALNET_RPC_URL:-${LEZ_RPC_URL:-http://127.0.0.1:3040}}"
    export DISTRIBUTIONX_RELAYER_URL="${DISTRIBUTIONX_RELAYER_URL:-localnet}"
    export DISTRIBUTIONX_ENV_FILE=/dev/null
    export RISC0_DEV_MODE=0
    default_local_submit_hooks
    if ! is_local_rpc "${LEZ_RPC_URL}"; then
      echo "E_DISTRIBUTIONX_LOCALNET_RPC_REQUIRED: ${LEZ_RPC_URL}" >&2
      exit 2
    fi
    if ! bash "${ROOT}/scripts/lez-fingerprint.sh" --rpc "${LEZ_RPC_URL}" \
      --expected-channel "$(printf '01%.0s' {1..32})" >/dev/null; then
      echo "E_DISTRIBUTIONX_LOCALNET_RPC_NOT_READY: ${LEZ_RPC_URL}" >&2
      echo "Start the pinned sequencer first, or use mode ci-localnet." >&2
      exit 2
    fi
    ;;
  private-localnet)
    load_env_file
    export LEZ_RPC_URL="${DISTRIBUTIONX_LOCALNET_RPC_URL:-${LEZ_RPC_URL:-http://127.0.0.1:3040}}"
    export DISTRIBUTIONX_RELAYER_URL="${DISTRIBUTIONX_RELAYER_URL:-localnet}"
    export DISTRIBUTIONX_ENV_FILE=/dev/null
    export RISC0_DEV_MODE=0
    default_local_submit_hooks
    mode=localnet
    if ! is_local_rpc "${LEZ_RPC_URL}"; then
      echo "E_DISTRIBUTIONX_LOCALNET_RPC_REQUIRED: ${LEZ_RPC_URL}" >&2
      exit 2
    fi
    if ! bash "${ROOT}/scripts/lez-fingerprint.sh" --rpc "${LEZ_RPC_URL}" \
      --expected-channel "$(printf '01%.0s' {1..32})" >/dev/null; then
      echo "E_DISTRIBUTIONX_LOCALNET_RPC_NOT_READY: ${LEZ_RPC_URL}" >&2
      echo "Start the LEZ sequencer first." >&2
      exit 2
    fi
    ;;
  testnet)
    # Manual-only entry point. There is no testnet job in CI; this mode is
    # kept for one-off ad-hoc testnet runs and is not part of the supported
    # demo flow. Requires the full set of LEZ_* / DISTRIBUTIONX_* secrets
    # listed below to be exported by the caller before running.
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

STATE_DIR="${DISTRIBUTIONX_STATE_DIR:-${ROOT}/target/distributionx-testnet}"
if [[ "${mode}" == "testnet" ]]; then
  umask 077
  LOG_DIR="${DISTRIBUTIONX_LIVE_LOG_DIR:-${STATE_DIR}/logs}"
else
  LOG_DIR="${DISTRIBUTIONX_LOCAL_LOG_DIR:-${ROOT}/docs/run-logs/e2e}"
fi
resolved_target="$(realpath -m "${ROOT}/target")"
resolved_state="$(realpath -m "${STATE_DIR}")"
[[ "${resolved_state}" == "${resolved_target}/"* && "${resolved_state}" != "${resolved_target}" ]] || {
  echo "E_DISTRIBUTIONX_STATE_DIR_UNSAFE_TO_RESET: ${resolved_state}" >&2
  exit 2
}
rm -rf "${STATE_DIR}"
mkdir -p "${LOG_DIR}" "${STATE_DIR}"
if [[ "${mode}" == "testnet" ]]; then
  chmod 700 "${STATE_DIR}" "${LOG_DIR}"
else
  rm -f "${LOG_DIR}"/*.log "${LOG_DIR}"/*.json
fi
export DISTRIBUTIONX_STATE_DIR="${STATE_DIR}"
export DISTRIBUTIONX_REPO_ROOT="${ROOT}"
export DISTRIBUTIONX_AIRDROP_NAME="${DISTRIBUTIONX_AIRDROP_NAME:-demo-airdrop}"
export DISTRIBUTIONX_FUND_AMOUNT="${DISTRIBUTIONX_FUND_AMOUNT:-3000}"
export DISTRIBUTIONX_EXPIRY_UNIX="${DISTRIBUTIONX_EXPIRY_UNIX:-1893456000}"

if [[ "${mode}" == "localnet" ]]; then
  export LEE_WALLET_HOME_DIR="${LEE_WALLET_HOME_DIR:-${ROOT}/target/lez-v0.2.4-wallet}"
  export DISTRIBUTIONX_BOOTSTRAP_EVIDENCE_MODE="${DISTRIBUTIONX_BOOTSTRAP_EVIDENCE_MODE:-1}"
  BOOTSTRAP_ARGS=()
  if [[ "${CI_LOCALNET}" == "1" ]]; then
    BOOTSTRAP_ARGS+=(--clean)
  fi
  LEZ_DEPLOYER_WALLET="$(bash "${ROOT}/scripts/wallet-bootstrap.sh" "${BOOTSTRAP_ARGS[@]}")"
  export LEZ_DEPLOYER_WALLET
  if [[ -z "${DISTRIBUTIONX_RECOVERY_ADDRESS:-}" ]]; then
    BOOTSTRAP_RECEIPT="${DISTRIBUTIONX_WALLET_BOOTSTRAP_RECEIPT:-${ROOT}/target/lez-v0.2.4-wallet-bootstrap.json}"
    RECOVERY_CANDIDATE="$(jq -er '.recovery | strings | select(length > 0)' \
      "${BOOTSTRAP_RECEIPT}" 2>/dev/null || true)"
    if [[ -z "${RECOVERY_CANDIDATE}" ]]; then
      echo "E_DISTRIBUTIONX_LOCALNET_RECOVERY_ACCOUNT_MISSING: ${BOOTSTRAP_RECEIPT} has no validated recovery account" >&2
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
      cargo +1.94.0 build -p distributionx-cli --release
      export DISTRIBUTIONX_CLI="${ROOT}/target/release/distributionx-cli"
      ;;
    debug)
      cargo +1.94.0 build -p distributionx-cli
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

distributionx_run_step() {
  local name="$1"
  shift
  local log="${LOG_DIR}/${name}.log"
  "$@" >"${log}" 2>&1
  cat "${log}"
}

distributionx_run_step_with_notice() {
  local name="$1"
  local notice="$2"
  shift 2
  local log="${LOG_DIR}/${name}.log"
  printf '%s\n' "${notice}" | tee "${log}"
  "$@" 2>&1 | tee -a "${log}"
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

flag_enabled() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  [[ "${value,,}" =~ ^(1|true|yes|on)$ ]]
}

claim_destination_args() {
  printf '%s\n' --destination-packet "${STATE_DIR}/shielded_destination.json"
}

echo "DistributionX E2E"
echo "RISC0_DEV_MODE=${RISC0_DEV_MODE}"
echo "DISTRIBUTIONX_CLI=${DISTRIBUTIONX_CLI}"
SOURCE_COMMIT="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || printf unknown)"
if git -C "${ROOT}" diff --quiet --ignore-submodules HEAD -- 2>/dev/null \
  && [[ -z "$(git -C "${ROOT}" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
  SOURCE_DIRTY=0
else
  SOURCE_DIRTY=1
fi
echo "DISTRIBUTIONX_SOURCE_COMMIT=${SOURCE_COMMIT}"
echo "DISTRIBUTIONX_SOURCE_DIRTY=${SOURCE_DIRTY}"

USE_REVIEWER_FIXTURE="${DISTRIBUTIONX_USE_REVIEWER_FIXTURE:-}"
if [[ -z "${USE_REVIEWER_FIXTURE}" ]]; then
  if [[ "${mode}" == "localnet" ]]; then
    USE_REVIEWER_FIXTURE=1
  else
    USE_REVIEWER_FIXTURE=0
  fi
fi

if [[ "${mode}" == "testnet" && "${USE_REVIEWER_FIXTURE}" == "1" ]]; then
  echo "E_DISTRIBUTIONX_PUBLIC_FIXTURE_FORBIDDEN: deterministic reviewer fixtures are localnet-only" >&2
  exit 2
elif [[ "${mode}" == "testnet" ]]; then
  if [[ -z "${DISTRIBUTIONX_RECOVERY_ADDRESS:-}" ]]; then
    echo "E_DISTRIBUTIONX_TESTNET_RECOVERY_REQUIRED: use a fresh initialized LEZ testnet recovery account" >&2
    exit 2
  fi
  WALLET_OUTPUT="$(cli create-wallet --out-dir "${STATE_DIR}")"
  CLAIMANT_ACCOUNT="$(jq -er '.account' <<<"${WALLET_OUTPUT}")"
  CLAIMANT_HEX="${CLAIMANT_ACCOUNT#Public/}"
  [[ "${CLAIMANT_HEX}" =~ ^[0-9a-f]{64}$ ]] || {
    echo "E_DISTRIBUTIONX_TESTNET_CLAIMANT_INVALID" >&2
    exit 1
  }
  cli create-destination --out-dir "${STATE_DIR}" >/dev/null
  printf 'address,raw_amount\n%s,%s\n' \
    "${CLAIMANT_HEX}" "${DISTRIBUTIONX_FUND_AMOUNT}" > "${STATE_DIR}/eligible.csv"
  chmod 600 "${STATE_DIR}/eligible.csv" "${STATE_DIR}/wallet.seed" \
    "${STATE_DIR}/shielded_destination.json" \
    "${STATE_DIR}/shielded_destination_keys.json"
  jq -n \
    --arg status "SAMPLE_FIXTURE_OK" \
    --arg csv "${STATE_DIR}/eligible.csv" \
    --arg wallet "${STATE_DIR}/wallet.seed" \
    --arg account "${CLAIMANT_ACCOUNT}" \
    --arg destination "${STATE_DIR}/shielded_destination.json" \
    '{status:$status,csv:$csv,wallet:$wallet,claimant_account:$account,shielded_destination:$destination,random_source:"OsRng"}' \
    > "${LOG_DIR}/sample.log"
  cat "${LOG_DIR}/sample.log"
elif [[ "${USE_REVIEWER_FIXTURE}" == "1" ]]; then
  distributionx_run_step sample env DISTRIBUTIONX_STATE_DIR="${STATE_DIR}" "${ROOT}/scripts/install-reviewer-fixture.sh"
else
  distributionx_run_step sample cli sample-fixture --out-dir "${STATE_DIR}"
fi
assert_marker sample "SAMPLE_FIXTURE_OK"

USE_CUSTOM_TOKEN_SETTLEMENT="${DISTRIBUTIONX_USE_CUSTOM_TOKEN_SETTLEMENT:-0}"
if ! flag_enabled "${USE_CUSTOM_TOKEN_SETTLEMENT}"; then
  if [[ -z "${DISTRIBUTIONX_TOKEN_ID:-}" ]]; then
    TOKEN_OUTPUT="$(cli token-id --name "${DISTRIBUTIONX_AIRDROP_NAME}-compatibility-token")"
    DISTRIBUTIONX_TOKEN_ID="$(printf '%s\n' "${TOKEN_OUTPUT}" | json_string_field token_id)"
    export DISTRIBUTIONX_TOKEN_ID
  fi
  unset DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT
elif [[ -z "${DISTRIBUTIONX_TOKEN_ID:-}" || -z "${DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT:-}" ]]; then
  MINT_OUTPUT="$(cli mint-token --name "${DISTRIBUTIONX_AIRDROP_NAME}-token" --total-supply "${DISTRIBUTIONX_FUND_AMOUNT}")"
  printf '%s\n' "${MINT_OUTPUT}" > "${LOG_DIR}/mint-token.log"
  DISTRIBUTIONX_TOKEN_ID="$(printf '%s\n' "${MINT_OUTPUT}" | json_string_field token_id)"
  DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT="$(printf '%s\n' "${MINT_OUTPUT}" | json_string_field supply_account_id)"
  export DISTRIBUTIONX_TOKEN_ID
  export DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT
fi

if [[ -z "${DISTRIBUTIONX_RECOVERY_ADDRESS:-}" ]]; then
  DISTRIBUTIONX_RECOVERY_ADDRESS="$(json_string_field admin_account < "${LOG_DIR}/sample.log")"
  export DISTRIBUTIONX_RECOVERY_ADDRESS
fi

TOKEN_SOURCE_REQUIRED=0
if flag_enabled "${USE_CUSTOM_TOKEN_SETTLEMENT}"; then
  TOKEN_SOURCE_REQUIRED=1
fi
if [[ -z "${DISTRIBUTIONX_TOKEN_ID:-}" \
  || -z "${DISTRIBUTIONX_RECOVERY_ADDRESS:-}" \
  || ( "${TOKEN_SOURCE_REQUIRED}" == "1" && -z "${DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT:-}" ) ]]; then
  echo "E_DISTRIBUTIONX_SAMPLE_DERIVATION_FAILED" >&2
  exit 2
fi

distributionx_run_step deploy scripts/deploy.sh "--${mode}"
assert_marker deploy "DEPLOY_${mode^^}_OK"

TOKEN_SOURCE_ARGS=()
if [[ -n "${DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT:-}" ]]; then
  TOKEN_SOURCE_ARGS+=(--token-source-account "${DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT}")
fi

distributionx_run_step init cli init \
  --csv "${STATE_DIR}/eligible.csv" \
  --distributor "${LEZ_DEPLOYER_WALLET}" \
  --token "${DISTRIBUTIONX_TOKEN_ID}" \
  "${TOKEN_SOURCE_ARGS[@]}" \
  --rpc "${LEZ_RPC_URL}" \
  --expiry "${DISTRIBUTIONX_EXPIRY_UNIX}" \
  --recovery "${DISTRIBUTIONX_RECOVERY_ADDRESS}"
assert_marker init "INIT_OK"

distributionx_run_step fund cli fund --airdrop "${DISTRIBUTIONX_AIRDROP_NAME}" --amount "${DISTRIBUTIONX_FUND_AMOUNT}"
assert_marker fund "FUND_OK"

mapfile -t CLAIM_DESTINATION_ARGS < <(claim_destination_args)
RISC0_WORK_DIR="${STATE_DIR}/risc0-groth16-work"
mkdir -p "${RISC0_WORK_DIR}"
chmod 700 "${RISC0_WORK_DIR}"
export RISC0_WORK_DIR
distributionx_run_step_with_notice prove "RISC0_DEV_MODE=${RISC0_DEV_MODE} PROOF_GENERATION_START command=distributionx-cli prove" cli prove \
  --airdrop "${DISTRIBUTIONX_AIRDROP_NAME}" \
  --bundle "${STATE_DIR}/bundle.json" \
  --wallet "${STATE_DIR}/wallet.seed" \
  "${CLAIM_DESTINATION_ARGS[@]}"
unset RISC0_WORK_DIR
assert_marker prove "RISC0_DEV_MODE=0"
assert_marker prove "PROVE_LOCAL_OK"
assert_marker prove "claim_destination_commitment"
assert_marker prove '"risc0_real_proof":"OK"'

claim_private_flag="${DISTRIBUTIONX_USE_CLAIM_PRIVATE:-0}"
claim_private_flag="${claim_private_flag#"${claim_private_flag%%[![:space:]]*}"}"
claim_private_flag="${claim_private_flag%"${claim_private_flag##*[![:space:]]}"}"
if [[ "${claim_private_flag}" =~ ^(1|true|yes|on)$ ]]; then
  if ! jq -e '.private_claim != null and .recipient_npk != null and .recipient_vpk != null' "${DISTRIBUTIONX_SERIALIZED_LEZ_TX}" >/dev/null; then
    echo "DISTRIBUTIONX_USE_CLAIM_PRIVATE is set but claim.tx is missing private_claim/recipient_npk/recipient_vpk" >&2
    exit 1
  fi
else
  if ! jq -e '.recipient_npk != null and .recipient_vpk != null' "${DISTRIBUTIONX_SERIALIZED_LEZ_TX}" >/dev/null; then
    echo "claim did not produce a shielded destination packet (recipient_npk/recipient_vpk missing)" >&2
    exit 1
  fi
  # Default path is now claim_ppe (privacy-preserving execution): claim.tx carries the witness
  # locally as the PPE prover's input. On-chain witness privacy is guaranteed by the PPE message
  # format (it carries no instruction data / witness fields), not by stripping the local claim.tx.
  if ! jq -e '.private_claim != null' "${DISTRIBUTIONX_SERIALIZED_LEZ_TX}" >/dev/null; then
    echo "claim_ppe path: claim.tx is missing the private_claim witness needed for PPE proving" >&2
    exit 1
  fi
fi

if grep -q "claim_address" "${STATE_DIR}/proof.json"; then
  echo "proof journal still contains claim_address" >&2
  exit 1
fi

distributionx_run_step verify-before-claim cli verify \
  --airdrop "${DISTRIBUTIONX_AIRDROP_NAME}" \
  --proof "${STATE_DIR}/proof.json"
assert_marker verify-before-claim "VERIFY_OK"
assert_marker verify-before-claim '"risc0_receipt_verify":"verified"'

distributionx_run_step claim cli claim \
  --airdrop "${DISTRIBUTIONX_AIRDROP_NAME}" \
  --proof "${STATE_DIR}/proof.json" \
  --relayer "${DISTRIBUTIONX_RELAYER_URL}" \
  --serialized-lez-tx "${DISTRIBUTIONX_SERIALIZED_LEZ_TX}"
assert_marker claim "CLAIM_OK"

if cli claim --airdrop "${DISTRIBUTIONX_AIRDROP_NAME}" --proof "${STATE_DIR}/proof.json" --relayer "${DISTRIBUTIONX_RELAYER_URL}" --serialized-lez-tx "${DISTRIBUTIONX_SERIALIZED_LEZ_TX}" >"${LOG_DIR}/double-claim.log" 2>&1; then
  echo "double claim unexpectedly succeeded" >&2
  exit 1
fi
cat "${LOG_DIR}/double-claim.log"
assert_marker double-claim "E_ALREADY_CLAIMED"
echo "DISTRIBUTIONX_DUPLICATE_REJECTED_LOCALLY state.nullifiers"

CLOSE_AFTER_E2E="${DISTRIBUTIONX_CLOSE_AFTER_E2E:-}"
if [[ -z "${CLOSE_AFTER_E2E}" ]]; then
  if [[ "${mode}" == "testnet" ]]; then
    CLOSE_AFTER_E2E=0
  else
    CLOSE_AFTER_E2E=1
  fi
fi
if flag_enabled "${CLOSE_AFTER_E2E}"; then
  distributionx_run_step close cli close --airdrop "${DISTRIBUTIONX_AIRDROP_NAME}"
  assert_marker close "CLOSE_OK"
else
  echo "DISTRIBUTIONX_CLOSE_SKIPPED mode=${mode}"
fi

if [[ -x "${ROOT}/scripts/extract-cu.sh" ]]; then
  bash "${ROOT}/scripts/extract-cu.sh" >/dev/null
fi

echo "DISTRIBUTIONX_E2E_PASS logs=${LOG_DIR}"
if [[ "${CI_LOCALNET}" == "1" ]]; then
  echo "DISTRIBUTIONX_LOCALNET_E2E_PASS rpc=${LEZ_RPC_URL} logs=${LOG_DIR}"
  write_ci_summary "Passed" "real local sequencer demo completed against ${LEZ_RPC_URL}"
fi
