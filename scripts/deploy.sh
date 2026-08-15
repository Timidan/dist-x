#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
if [[ "${MODE}" != "--testnet" && "${MODE}" != "--localnet" ]]; then
  echo "usage: scripts/deploy.sh --testnet | --localnet" >&2
  exit 64
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${DISTRIBUTIONX_STATE_DIR:-${ROOT}/target/distributionx-testnet}"
CANONICAL_LEZ_REPO="${ROOT}/.scaffold/cache/repos/lez/v0.2.4"
CANONICAL_CLI_BIN="${ROOT}/target/release/distributionx-cli"
LEZ_REPO="${DISTRIBUTIONX_LEZ_REPO:-${CANONICAL_LEZ_REPO}}"
RPC_URL="${LEZ_RPC_URL:-}"
IDL="${ROOT}/crates/distributionx-program/idl/distributionx.json"
PROGRAM_BINARY="${ROOT}/target/riscv-guest/example_program_deployment_methods/example_program_deployment_programs/riscv32im-risc0-zkvm-elf/release/distributionx.bin"
CLI_BIN="${DISTRIBUTIONX_CLI:-${CANONICAL_CLI_BIN}}"
EVIDENCE_PROVENANCE="${DISTRIBUTIONX_EVIDENCE_PROVENANCE:-0}"

case "${EVIDENCE_PROVENANCE}" in
  0|1) ;;
  *) echo 'E_DISTRIBUTIONX_EVIDENCE_PROVENANCE_INVALID' >&2; exit 2 ;;
esac

if [[ "${EVIDENCE_PROVENANCE}" == 1 ]]; then
  [[ -z "${LEZ_DEPLOY_COMMAND:-}" && -z "${LEZ_WALLET_BIN:-}" && -z "${LEE_WALLET_HOME_DIR:-}" ]] \
    || { echo 'E_EVIDENCE_DEPLOY_OVERRIDE_FORBIDDEN' >&2; exit 2; }
  [[ "${LEZ_REPO}" == "${CANONICAL_LEZ_REPO}" && "${CLI_BIN}" == "${CANONICAL_CLI_BIN}" ]] \
    || { echo 'E_EVIDENCE_PATH_NONCANONICAL' >&2; exit 2; }
  EVIDENCE_PRIVATE_ROOT="${DISTRIBUTIONX_EVIDENCE_PRIVATE_ROOT:?DISTRIBUTIONX_EVIDENCE_PRIVATE_ROOT required}"
  WALLET_HOME="${DISTRIBUTIONX_EVIDENCE_WALLET_HOME:?DISTRIBUTIONX_EVIDENCE_WALLET_HOME required}"
  WALLET_CONFIG="${DISTRIBUTIONX_EVIDENCE_WALLET_CONFIG:?DISTRIBUTIONX_EVIDENCE_WALLET_CONFIG required}"
  [[ "${WALLET_HOME}" == "${EVIDENCE_PRIVATE_ROOT}/wallet" && "${WALLET_CONFIG}" == "${WALLET_HOME}/wallet_config.json" ]] \
    || { echo 'E_EVIDENCE_WALLET_PATH_NONPRIVATE' >&2; exit 2; }
  WALLET_BIN="${ROOT}/target/lez-v0.2.4-build/release/wallet"
  WALLET_SOURCE_HOME="${ROOT}/target/lez-v0.2.4-wallet"
else
  WALLET_BIN="${LEZ_WALLET_BIN:-${ROOT}/target/lez-v0.2.4-build/release/wallet}"
  WALLET_HOME="${LEE_WALLET_HOME_DIR:-${ROOT}/target/lez-v0.2.4-wallet}"
  WALLET_CONFIG="${WALLET_HOME}/wallet_config.json"
fi
LEZ_COMMIT="$(bash "${ROOT}/scripts/lez-source-guard.sh" "${LEZ_REPO}")"

if [[ "${MODE}" == "--localnet" ]]; then
  RPC_URL="${RPC_URL:-http://127.0.0.1:3040}"
elif [[ -z "${RPC_URL}" ]]; then
  echo "E_LEZ_RPC_URL_REQUIRED" >&2
  exit 2
fi

mkdir -p "${OUT_DIR}"
cd "${ROOT}"
export CARGO_HOME="${CARGO_HOME:-${ROOT}/target/cargo-home}"

# The project and LEZ v0.2.4 both resolve the v0.5.3 circuits. Prefer an
# explicitly supplied installation, then the repository copy, then the exact
# user cache. No legacy build-output paths are injected.
cached_lbc="${HOME}/.cache/logos/blockchain/logos-blockchain-circuits-v0.5.3-linux-x86_64"
if [[ -z "${LBC_ROOT_DIR:-}" ]]; then
  if [[ -d "${ROOT}/vendor/logos-blockchain-circuits/signature" && -d "${ROOT}/vendor/logos-blockchain-circuits/lib" ]]; then
    export LBC_ROOT_DIR="${ROOT}/vendor/logos-blockchain-circuits"
  elif [[ -d "${cached_lbc}/signature" && -d "${cached_lbc}/lib" ]]; then
    export LBC_ROOT_DIR="${cached_lbc}"
  fi
fi

if [[ "${MODE}" == "--localnet" ]]; then
  debug_channel="$(printf '01%.0s' {1..32})"
  bash "${ROOT}/scripts/lez-fingerprint.sh" --rpc "${RPC_URL}" \
    --expected-channel "${debug_channel}" >/dev/null
else
  bash "${ROOT}/scripts/lez-fingerprint.sh" --rpc "${RPC_URL}" >/dev/null
fi

if [[ "${EVIDENCE_PROVENANCE}" == 1 ]]; then
  [[ -n "${DISTRIBUTIONX_EVIDENCE_CLI_SHA256:-}" ]] \
    || { echo 'E_EVIDENCE_CLI_SHA256_REQUIRED' >&2; exit 2; }
  [[ -x "${CLI_BIN}" ]] || { echo "E_DISTRIBUTIONX_CLI_NOT_EXECUTABLE: ${CLI_BIN}" >&2; exit 2; }
  [[ "$(sha256sum "${CLI_BIN}" | awk '{print $1}')" == "${DISTRIBUTIONX_EVIDENCE_CLI_SHA256}" ]] \
    || { echo 'E_EVIDENCE_CLI_SHA256_MISMATCH' >&2; exit 2; }
  cargo +1.94.0 build -q --locked --release \
    -p distributionx-program --features spel-idl \
    -p example_program_deployment_methods
else
  cargo +1.94.0 build -q --locked --release \
    -p distributionx-program --features spel-idl \
    -p example_program_deployment_methods \
    -p distributionx-cli
fi
[[ -x "${CLI_BIN}" ]] || { echo "E_DISTRIBUTIONX_CLI_NOT_EXECUTABLE: ${CLI_BIN}" >&2; exit 2; }
if [[ "${EVIDENCE_PROVENANCE}" == 1 ]]; then
  [[ "$(sha256sum "${CLI_BIN}" | awk '{print $1}')" == "${DISTRIBUTIONX_EVIDENCE_CLI_SHA256}" ]] \
    || { echo 'E_EVIDENCE_CLI_SHA256_MISMATCH' >&2; exit 2; }
fi

image_id_hex_from_methods_rs() {
  python3 - "${ROOT}" <<'PY'
import glob
import os
import re
import sys

root = sys.argv[1]
paths = glob.glob(os.path.join(
    root,
    "target/release/build/example_program_deployment_methods-*/out/methods.rs",
))
if not paths:
    raise SystemExit("methods.rs not found")
path = max(paths, key=os.path.getmtime)
text = open(path, "r", encoding="utf-8").read()
match = re.search(r"DISTRIBUTIONX_ID:\s*\[u32;\s*8\]\s*=\s*\[([^\]]+)\]", text)
if not match:
    raise SystemExit(f"DISTRIBUTIONX_ID not found in {path}")
words = [int(part.strip()) for part in match.group(1).split(",") if part.strip()]
if len(words) != 8:
    raise SystemExit(f"DISTRIBUTIONX_ID has {len(words)} words in {path}")
print("".join(word.to_bytes(4, "little").hex() for word in words))
PY
}

program_deployment_tx_hash() {
  python3 - "${PROGRAM_BINARY}" <<'PY'
import hashlib
import struct
import sys

bytecode = open(sys.argv[1], "rb").read()
print(hashlib.sha256(struct.pack("<I", len(bytecode)) + bytecode).hexdigest())
PY
}

prepare_evidence_wallet_home() {
  [[ "${EVIDENCE_PROVENANCE}" == 1 ]] || return 0
  [[ -d "${WALLET_HOME}" && -f "${WALLET_CONFIG}" ]] \
    || { echo "E_EVIDENCE_WALLET_CONFIG_MISSING: ${WALLET_CONFIG}" >&2; return 2; }
  jq -e --arg rpc "${RPC_URL}" \
    '.sequencers == [{sequencer_addr:$rpc,basic_auth:null}]' "${WALLET_CONFIG}" >/dev/null \
    || { echo 'E_EVIDENCE_WALLET_RPC_MISMATCH' >&2; return 2; }
  [[ -f "${WALLET_SOURCE_HOME}/storage.json" ]] \
    || { echo "E_EVIDENCE_WALLET_SOURCE_STORAGE_MISSING: ${WALLET_SOURCE_HOME}/storage.json" >&2; return 2; }
  cp --preserve=mode "${WALLET_SOURCE_HOME}/storage.json" "${WALLET_HOME}/storage.json"
  if [[ -f "${WALLET_SOURCE_HOME}/statistics.json" ]]; then
    cp --preserve=mode "${WALLET_SOURCE_HOME}/statistics.json" "${WALLET_HOME}/statistics.json"
  fi
}

METHOD_JSON="$("${CLI_BIN}" method-id)"
METHOD_IMAGE_ID_HEX="$(jq -er '.image_id_hex' <<<"${METHOD_JSON}")"
PROGRAM_IMAGE_ID_HEX="$(image_id_hex_from_methods_rs)"
[[ "${METHOD_IMAGE_ID_HEX}" =~ ^[0-9a-f]{64}$ ]] || { echo "E_METHOD_ID_UNAVAILABLE" >&2; exit 1; }
[[ "${PROGRAM_IMAGE_ID_HEX}" =~ ^[0-9a-f]{64}$ ]] || { echo "E_PROGRAM_IMAGE_ID_UNAVAILABLE" >&2; exit 1; }
[[ -f "${PROGRAM_BINARY}" ]] || { echo "E_PROGRAM_BINARY_MISSING: ${PROGRAM_BINARY}" >&2; exit 1; }

run_wallet_deploy() {
  prepare_evidence_wallet_home
  [[ -x "${WALLET_BIN}" ]] || { echo "E_LEZ_WALLET_MISSING: ${WALLET_BIN}" >&2; return 2; }
  [[ -f "${WALLET_HOME}/storage.json" ]] \
    || { echo "E_LEZ_WALLET_STORAGE_MISSING: ${WALLET_HOME}/storage.json" >&2; return 2; }
  [[ -f "${WALLET_CONFIG}" ]] \
    || { echo "E_LEZ_WALLET_CONFIG_MISSING: ${WALLET_CONFIG}" >&2; return 2; }

  local raw_output filtered_output status
  raw_output="$(mktemp)"
  if env LEE_WALLET_HOME_DIR="${WALLET_HOME}" \
    "${WALLET_BIN}" deploy-program "${PROGRAM_BINARY}" >"${raw_output}" 2>&1; then
    status=0
  else
    status=$?
  fi
  filtered_output="$(sed '/^Transaction data is /d' "${raw_output}")"
  rm -f -- "${raw_output}"
  printf '%s\n' "${filtered_output}"
  [[ "${status}" == "0" ]] || return "${status}"
}

run_deploy_command() {
  if [[ "${EVIDENCE_PROVENANCE}" == 1 ]]; then
    run_wallet_deploy
    return
  fi
  local command="${LEZ_DEPLOY_COMMAND:-wallet}"
  case "${command}" in
    ""|auto|wallet|"lgs deploy distributionx --json") run_wallet_deploy ;;
    *) bash -c "${command}" ;;
  esac
}

extract_json_field() {
  local output="$1"
  shift
  local key value
  for key in "$@"; do
    value="$(sed -n "s/.*\"${key}\":\"\\([^\"]*\\)\".*/\\1/p" <<<"${output}" | tail -1)"
    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
  done
}

included_block_from_rpc() {
  local tx_hash="$1"
  local request response block_id
  request="$(jq -nc --arg hash "${tx_hash}" '{jsonrpc:"2.0",id:1,method:"getTransaction",params:[$hash]}')"
  for _ in $(seq 1 "${DISTRIBUTIONX_DEPLOY_INCLUSION_ATTEMPTS:-20}"); do
    response="$(curl --fail-with-body --silent --show-error --max-time 15 \
      --header 'content-type: application/json' --data "${request}" "${RPC_URL}")" || return 1
    if jq -e '.error == null and (.result | type == "array" and length == 2)' \
      >/dev/null <<<"${response}"; then
      block_id="$(jq -er '.result[1] | numbers' <<<"${response}")" || return 1
      printf '%s\n' "${block_id}"
      return 0
    fi
    if ! jq -e '.error == null and has("result")' >/dev/null <<<"${response}"; then
      echo "E_DEPLOY_TRANSACTION_RPC_RESPONSE: ${response}" >&2
      return 1
    fi
    sleep 1
  done
  return 1
}

if ! DEPLOY_OUTPUT="$(run_deploy_command 2>&1)"; then
  printf '%s\n' "${DEPLOY_OUTPUT}" | tee "${OUT_DIR}/deploy-output.log"
  echo "E_DEPLOY_${MODE#--}_FAILED" >&2
  exit 1
fi
printf '%s\n' "${DEPLOY_OUTPUT}" | tee "${OUT_DIR}/deploy-output.log"

REPORTED_PROGRAM_ID="$(extract_json_field "${DEPLOY_OUTPUT}" program_id || true)"
if [[ "${EVIDENCE_PROVENANCE}" == 1 ]]; then
  [[ -z "${REPORTED_PROGRAM_ID}" || "${REPORTED_PROGRAM_ID}" == "${PROGRAM_IMAGE_ID_HEX}" ]] \
    || { echo "E_DEPLOY_PROGRAM_ID_MISMATCH: reported=${REPORTED_PROGRAM_ID} expected=${PROGRAM_IMAGE_ID_HEX}" >&2; exit 1; }
  PROGRAM_ID="${PROGRAM_IMAGE_ID_HEX}"
  PROGRAM_ID_SOURCE="risc0_program_image_id"
else
  PROGRAM_ID="${REPORTED_PROGRAM_ID}"
  PROGRAM_ID_SOURCE="deploy_output"
  if [[ -z "${PROGRAM_ID}" ]]; then
    PROGRAM_ID="${PROGRAM_IMAGE_ID_HEX}"
    PROGRAM_ID_SOURCE="risc0_program_image_id"
  fi
fi

REPORTED_DEPLOY_TX_HASH="$(sed -n 's/^Transaction hash is \([0-9a-f]\{64\}\)$/\1/p' <<<"${DEPLOY_OUTPUT}" | tail -1)"
if [[ -z "${REPORTED_DEPLOY_TX_HASH}" ]]; then
  REPORTED_DEPLOY_TX_HASH="$(extract_json_field "${DEPLOY_OUTPUT}" tx_hash tx_id transaction_hash transaction_id || true)"
fi
DETERMINISTIC_PROGRAM_DEPLOYMENT_TX_HASH="$(program_deployment_tx_hash)"
if [[ "${EVIDENCE_PROVENANCE}" == 1 ]]; then
  [[ -z "${REPORTED_DEPLOY_TX_HASH}" || "${REPORTED_DEPLOY_TX_HASH}" == "${DETERMINISTIC_PROGRAM_DEPLOYMENT_TX_HASH}" ]] \
    || { echo "E_DEPLOY_TRANSACTION_HASH_MISMATCH: reported=${REPORTED_DEPLOY_TX_HASH} expected=${DETERMINISTIC_PROGRAM_DEPLOYMENT_TX_HASH}" >&2; exit 1; }
  DEPLOY_TX_HASH="${DETERMINISTIC_PROGRAM_DEPLOYMENT_TX_HASH}"
  DEPLOY_TX_HASH_SOURCE="deterministic_program_deployment_hash"
else
  DEPLOY_TX_HASH="${REPORTED_DEPLOY_TX_HASH}"
  DEPLOY_TX_HASH_SOURCE="wallet_inclusion_output"
  if [[ -z "${DEPLOY_TX_HASH}" ]]; then
    DEPLOY_TX_HASH="${DETERMINISTIC_PROGRAM_DEPLOYMENT_TX_HASH}"
    DEPLOY_TX_HASH_SOURCE="deterministic_program_deployment_hash"
  fi
fi
[[ "${DEPLOY_TX_HASH}" =~ ^[0-9a-f]{64}$ ]] \
  || { echo "E_DEPLOY_TRANSACTION_HASH_INVALID: ${DEPLOY_TX_HASH}" >&2; exit 1; }

WALLET_BLOCK_ID="$(sed -n 's/^Transaction is included in block \([0-9][0-9]*\)$/\1/p' <<<"${DEPLOY_OUTPUT}" | tail -1)"
RPC_BLOCK_ID="$(included_block_from_rpc "${DEPLOY_TX_HASH}")" \
  || { echo "E_DEPLOY_TRANSACTION_NOT_INCLUDED: ${DEPLOY_TX_HASH}" >&2; exit 1; }
if [[ -n "${WALLET_BLOCK_ID}" && "${WALLET_BLOCK_ID}" != "${RPC_BLOCK_ID}" ]]; then
  echo "E_DEPLOY_BLOCK_MISMATCH: wallet=${WALLET_BLOCK_ID} rpc=${RPC_BLOCK_ID}" >&2
  exit 1
fi

MODE_NAME="${MODE#--}"
STATUS="DEPLOY_${MODE_NAME^^}_OK"
# LEZ v0.2.4 program deployment is unsigned. Do not infer a signer from an
# unrelated funded distribution account or from unverified command output.
DEPLOY_SIGNER_ACCOUNT=""

jq -n \
  --arg status "${STATUS}" \
  --arg mode "${MODE_NAME}" \
  --arg rpc_url "${RPC_URL}" \
  --arg lez_commit "${LEZ_COMMIT}" \
  --arg program_id "${PROGRAM_ID}" \
  --arg program_id_source "${PROGRAM_ID_SOURCE}" \
  --arg deploy_tx_hash "${DEPLOY_TX_HASH}" \
  --arg deploy_tx_hash_source "${DEPLOY_TX_HASH_SOURCE}" \
  --arg deterministic_program_deployment_tx_hash "${DETERMINISTIC_PROGRAM_DEPLOYMENT_TX_HASH}" \
  --argjson deploy_block_id "${RPC_BLOCK_ID}" \
  --arg deploy_wallet_bin "${WALLET_BIN}" \
  --arg deploy_wallet_home "${WALLET_HOME}" \
  --arg deploy_signer_account "${DEPLOY_SIGNER_ACCOUNT}" \
  --arg program_image_id_hex "${PROGRAM_IMAGE_ID_HEX}" \
  --arg method_image_id_hex "${METHOD_IMAGE_ID_HEX}" \
  --arg idl "${IDL}" \
  --arg deploy_output_log "${OUT_DIR}/deploy-output.log" \
  '{
    status: $status,
    mode: $mode,
    rpc_url: $rpc_url,
    lez_commit: $lez_commit,
    program_id: $program_id,
    program_id_source: $program_id_source,
    deploy_tx_hash: $deploy_tx_hash,
    deploy_tx_hash_source: $deploy_tx_hash_source,
    deterministic_program_deployment_tx_hash: $deterministic_program_deployment_tx_hash,
    deploy_block_id: $deploy_block_id,
    inclusion_rechecked_via_rpc: true,
    deploy_wallet_bin: $deploy_wallet_bin,
    deploy_wallet_home: $deploy_wallet_home,
    deploy_signer_account: (if $deploy_signer_account == "" then null else $deploy_signer_account end),
    program_image_id_hex: $program_image_id_hex,
    method_image_id_hex: $method_image_id_hex,
    idl: $idl,
    deploy_output_log: $deploy_output_log
  }' > "${OUT_DIR}/deployment.json"

printf '%s program_id=%s deploy_tx_hash=%s block_id=%s metadata=%s\n' \
  "${STATUS}" "${PROGRAM_ID}" "${DEPLOY_TX_HASH}" "${RPC_BLOCK_ID}" \
  "${OUT_DIR}/deployment.json"
