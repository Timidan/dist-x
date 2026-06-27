#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
if [[ "${MODE}" != "--testnet" && "${MODE}" != "--localnet" ]]; then
  echo "usage: scripts/deploy.sh --testnet | --localnet" >&2
  exit 64
fi

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "E_${name}_REQUIRED" >&2
    exit 2
  fi
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${DISTRIBUTIONX_STATE_DIR:-${ROOT}/target/distributionx-testnet}"
mkdir -p "${OUT_DIR}"

cd "${ROOT}"
CARGO_HOME="${CARGO_HOME:-${ROOT}/target/cargo-home}"
export CARGO_HOME
RECURSION_SRC_PATH="${RECURSION_SRC_PATH:-${ROOT}/target/debug/build/risc0-circuit-recursion-a1c9201d1968cbdd/out/recursion_zkr.zip}"
if [[ -f "${RECURSION_SRC_PATH}" ]]; then
  export RECURSION_SRC_PATH
fi
RAPIDSNARK_LIB_DIR="${RAPIDSNARK_LIB_DIR:-${ROOT}/target/lez-rc5-build/release/build/rust-rapidsnark-4e8ffacb0415e9be/out/rapidsnark/x86_64}"
if [[ -d "${RAPIDSNARK_LIB_DIR}" ]]; then
  export RAPIDSNARK_LIB_DIR
fi
LOGOS_BLOCKCHAIN_CIRCUITS="${LOGOS_BLOCKCHAIN_CIRCUITS:-${ROOT}/vendor/logos-blockchain-circuits}"
cached_lbc="${HOME}/.cache/logos/blockchain/logos-blockchain-circuits-v0.5.3-linux-x86_64"
if [[ -z "${LBC_ROOT_DIR:-}" ]]; then
  if [[ -d "${LOGOS_BLOCKCHAIN_CIRCUITS}/signature" && -d "${LOGOS_BLOCKCHAIN_CIRCUITS}/lib" ]]; then
    export LBC_ROOT_DIR="${LOGOS_BLOCKCHAIN_CIRCUITS}"
  elif [[ -d "${cached_lbc}/signature" && -d "${cached_lbc}/lib" ]]; then
    export LBC_ROOT_DIR="${cached_lbc}"
  fi
fi
cargo build -q -p distributionx-program --features spel-idl
cargo build -q -p example_program_deployment_methods

image_id_hex_from_methods_rs() {
  python3 - "${ROOT}" <<'PY'
import glob
import os
import re
import sys

root = sys.argv[1]
paths = glob.glob(os.path.join(
    root,
    "target/debug/build/example_program_deployment_methods-*/out/methods.rs",
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

METHOD_JSON="$(cargo run -q -p distributionx-cli -- method-id)"
METHOD_IMAGE_ID_HEX="$(printf '%s\n' "${METHOD_JSON}" | sed -n 's/.*"image_id_hex":"\([0-9a-f]*\)".*/\1/p')"
if [[ "${#METHOD_IMAGE_ID_HEX}" != "64" ]]; then
  echo "E_METHOD_ID_UNAVAILABLE" >&2
  exit 1
fi
PROGRAM_IMAGE_ID_HEX="$(image_id_hex_from_methods_rs)"
if [[ "${#PROGRAM_IMAGE_ID_HEX}" != "64" ]]; then
  echo "E_PROGRAM_IMAGE_ID_UNAVAILABLE" >&2
  exit 1
fi

IDL="${ROOT}/crates/distributionx-program/idl/distributionx.json"
PROGRAM_BINARY="${ROOT}/target/riscv-guest/example_program_deployment_methods/example_program_deployment_programs/riscv32im-risc0-zkvm-elf/release/distributionx.bin"

program_deployment_tx_hash() {
  python3 - "${PROGRAM_BINARY}" <<'PY'
import hashlib
import struct
import sys

bytecode = open(sys.argv[1], "rb").read()
# LEZ ProgramDeploymentTransaction is Borsh({ message: { bytecode: Vec<u8> } }).
# Vec<u8> serializes as a u32 little-endian length followed by raw bytes.
print(hashlib.sha256(struct.pack("<I", len(bytecode)) + bytecode).hexdigest())
PY
}

deploy_wallet_bin() {
  local lez_repo="${DISTRIBUTIONX_LEZ_REPO:-${ROOT}/.scaffold/cache/repos/lez/rc5}"
  printf '%s\n' "${LEZ_WALLET_BIN:-${ROOT}/target/lez-rc5-build/release/wallet}"
}

deploy_wallet_home() {
  if [[ -n "${LEE_WALLET_HOME_DIR:-}" ]]; then
    printf '%s\n' "${LEE_WALLET_HOME_DIR}"
  elif [[ -n "${NSSA_WALLET_HOME_DIR:-}" ]]; then
    printf '%s\n' "${NSSA_WALLET_HOME_DIR}"
  elif [[ -d "${ROOT}/.scaffold/wallet" ]]; then
    printf '%s\n' "${ROOT}/.scaffold/wallet"
  else
    printf '%s\n' "${HOME}/.lee/wallet"
  fi
}

run_wallet_deploy() {
  local wallet_bin wallet_home
  wallet_bin="$(deploy_wallet_bin)"
  wallet_home="$(deploy_wallet_home)"
  if [[ ! -x "${wallet_bin}" ]]; then
    echo "E_LEZ_WALLET_MISSING: ${wallet_bin}" >&2
    return 2
  fi
  if [[ ! -f "${wallet_home}/storage.json" ]]; then
    echo "E_LEZ_WALLET_STORAGE_MISSING: ${wallet_home}/storage.json" >&2
    return 2
  fi

  echo "$ LEE_WALLET_HOME_DIR=${wallet_home} ${wallet_bin} deploy-program ${PROGRAM_BINARY}"
  local wallet_output
  wallet_output="$(env LEE_WALLET_HOME_DIR="${wallet_home}" "${wallet_bin}" deploy-program "${PROGRAM_BINARY}" 2>&1)" || {
    printf '%s\n' "${wallet_output}"
    return 1
  }
  printf '%s\n' "${wallet_output}"
  if printf '%s\n' "${wallet_output}" | grep -Eq '(^Error:|Transaction submission error|Connection refused)'; then
    return 1
  fi
  echo "OK distributionx submitted"
  echo "Note: LEZ wallet confirms submission by exit status but does not currently print an inclusion receipt."
}

run_deploy_command() {
  local command="${1:-auto}"
  case "${command}" in
    ""|"auto"|"wallet"|"lgs deploy distributionx --json")
      run_wallet_deploy
      ;;
    *)
      bash -c "${command}"
      ;;
  esac
}

extract_deploy_field() {
  local output="$1"
  shift
  local key value
  for key in "$@"; do
    value="$(printf '%s\n' "${output}" | sed -n "s/.*\"${key}\":\"\\([^\"]*\\)\".*/\\1/p" | tail -1)"
    if [[ -n "${value}" ]]; then
      printf '%s\n' "${value}"
      return 0
    fi
  done
}

json_string_or_null() {
  local value="${1:-}"
  if [[ -z "${value}" ]]; then
    printf 'null'
  else
    printf '"%s"' "${value}"
  fi
}

if [[ "${MODE}" == "--localnet" ]]; then
  export LEZ_RPC_URL="${LEZ_RPC_URL:-http://127.0.0.1:3040}"
  http_code="$(curl --max-time 2 -sS -o /dev/null -w '%{http_code}' "${LEZ_RPC_URL}" 2>/dev/null || true)"
  if [[ -z "${http_code}" || "${http_code}" == "000" ]]; then
    echo "E_DISTRIBUTIONX_LOCALNET_RPC_NOT_READY: ${LEZ_RPC_URL}" >&2
    exit 2
  fi

  export DISTRIBUTIONX_REPO_ROOT="${ROOT}"
  export DISTRIBUTIONX_IDL="${IDL}"
  export DISTRIBUTIONX_PROGRAM_CRATE="${ROOT}/crates/distributionx-program"
  export DISTRIBUTIONX_PROGRAM_BINARY="${PROGRAM_BINARY}"
  export DISTRIBUTIONX_PROGRAM_IMAGE_ID_HEX="${PROGRAM_IMAGE_ID_HEX}"
  export DISTRIBUTIONX_METHOD_IMAGE_ID_HEX="${METHOD_IMAGE_ID_HEX}"
  export DISTRIBUTIONX_DEPLOYMENT_OUT="${OUT_DIR}/deployment.json"

  LOCAL_DEPLOY_COMMAND="${LEZ_DEPLOY_COMMAND:-}"
  if [[ -z "${LOCAL_DEPLOY_COMMAND}" ]]; then
    if ! command -v lgs >/dev/null 2>&1; then
      echo "E_LEZ_DEPLOY_COMMAND_REQUIRED: set LEZ_DEPLOY_COMMAND or install lgs" >&2
      exit 2
    fi
    LOCAL_DEPLOY_COMMAND='lgs deploy distributionx --json'
  fi

  if ! DEPLOY_OUTPUT="$(run_deploy_command "${LOCAL_DEPLOY_COMMAND}" 2>&1)"; then
    printf '%s\n' "${DEPLOY_OUTPUT}" | tee "${OUT_DIR}/deploy-output.log"
    echo "E_DEPLOY_LOCALNET_FAILED" >&2
    exit 1
  fi
  printf '%s\n' "${DEPLOY_OUTPUT}" | tee "${OUT_DIR}/deploy-output.log"

  PROGRAM_ID="$(printf '%s\n' "${DEPLOY_OUTPUT}" | sed -n 's/.*"program_id":"\([^"]*\)".*/\1/p' | tail -1)"
  PROGRAM_ID_SOURCE="deploy_output"
  if [[ -z "${PROGRAM_ID}" ]]; then
    PROGRAM_ID="${PROGRAM_IMAGE_ID_HEX}"
    PROGRAM_ID_SOURCE="risc0_program_image_id"
  fi
  DEPLOY_TX_HASH="$(extract_deploy_field "${DEPLOY_OUTPUT}" tx_hash tx_id transaction_hash transaction_id)"
  DEPLOY_TX_HASH_SOURCE="deploy_output"
  if [[ -z "${DEPLOY_TX_HASH}" ]]; then
    DEPLOY_TX_HASH="$(program_deployment_tx_hash)"
    DEPLOY_TX_HASH_SOURCE="local_lez_program_deployment_transaction_hash"
  fi
  DEPLOY_TX_HASH_JSON="$(json_string_or_null "${DEPLOY_TX_HASH}")"
  DEPLOY_WALLET_BIN="$(deploy_wallet_bin)"
  DEPLOY_WALLET_HOME="$(deploy_wallet_home)"
  DEPLOY_SIGNER_ACCOUNT="$(extract_deploy_field "${DEPLOY_OUTPUT}" signer deployer deployer_wallet account_id)"
  DEPLOY_SIGNER_ACCOUNT_SOURCE="deploy_output"
  if [[ -z "${DEPLOY_SIGNER_ACCOUNT}" ]]; then
    DEPLOY_SIGNER_ACCOUNT_SOURCE="missing_not_reported_by_deploy_command"
  fi
  DEPLOY_SIGNER_ACCOUNT_JSON="$(json_string_or_null "${DEPLOY_SIGNER_ACCOUNT}")"

  cat > "${OUT_DIR}/deployment.json" <<JSON
{
  "status": "DEPLOY_LOCALNET_OK",
  "mode": "localnet",
  "rpc_url": "${LEZ_RPC_URL}",
  "program_id": "${PROGRAM_ID}",
  "program_id_source": "${PROGRAM_ID_SOURCE}",
  "deploy_tx_hash": ${DEPLOY_TX_HASH_JSON},
  "deploy_tx_hash_source": "${DEPLOY_TX_HASH_SOURCE}",
  "deploy_wallet_bin": "${DEPLOY_WALLET_BIN}",
  "deploy_wallet_home": "${DEPLOY_WALLET_HOME}",
  "deploy_signer_account": ${DEPLOY_SIGNER_ACCOUNT_JSON},
  "deploy_signer_account_source": "${DEPLOY_SIGNER_ACCOUNT_SOURCE}",
  "program_image_id_hex": "${PROGRAM_IMAGE_ID_HEX}",
  "method_image_id_hex": "${METHOD_IMAGE_ID_HEX}",
  "idl": "${IDL}",
  "deploy_output_log": "${OUT_DIR}/deploy-output.log"
}
JSON

  echo "DEPLOY_LOCALNET_OK program_id=${PROGRAM_ID} deploy_tx_hash=${DEPLOY_TX_HASH:-missing} deploy_wallet_home=${DEPLOY_WALLET_HOME} metadata=${OUT_DIR}/deployment.json"
  exit 0
fi

# --testnet path
require_env LEZ_RPC_URL

export DISTRIBUTIONX_REPO_ROOT="${ROOT}"
export DISTRIBUTIONX_IDL="${IDL}"
export DISTRIBUTIONX_PROGRAM_CRATE="${ROOT}/crates/distributionx-program"
export DISTRIBUTIONX_PROGRAM_BINARY="${PROGRAM_BINARY}"
export DISTRIBUTIONX_PROGRAM_IMAGE_ID_HEX="${PROGRAM_IMAGE_ID_HEX}"
export DISTRIBUTIONX_METHOD_IMAGE_ID_HEX="${METHOD_IMAGE_ID_HEX}"
export DISTRIBUTIONX_DEPLOYMENT_OUT="${OUT_DIR}/deployment.json"

DEPLOY_COMMAND="${LEZ_DEPLOY_COMMAND:-auto}"
if ! DEPLOY_OUTPUT="$(run_deploy_command "${DEPLOY_COMMAND}" 2>&1)"; then
  printf '%s\n' "${DEPLOY_OUTPUT}" | tee "${OUT_DIR}/deploy-output.log"
  echo "E_DEPLOY_TESTNET_FAILED" >&2
  exit 1
fi
printf '%s\n' "${DEPLOY_OUTPUT}" | tee "${OUT_DIR}/deploy-output.log"

PROGRAM_ID="$(printf '%s\n' "${DEPLOY_OUTPUT}" | sed -n 's/.*"program_id":"\([^"]*\)".*/\1/p' | tail -1)"
PROGRAM_ID_SOURCE="deploy_output"
if [[ -z "${PROGRAM_ID}" ]]; then
  if printf '%s\n' "${DEPLOY_OUTPUT}" | grep -qi 'submitted'; then
    PROGRAM_ID="${PROGRAM_IMAGE_ID_HEX}"
    PROGRAM_ID_SOURCE="risc0_program_image_id_after_wallet_submit"
  else
    echo "E_PROGRAM_ID_NOT_RETURNED: LEZ_DEPLOY_COMMAND must print JSON containing program_id" >&2
    exit 1
  fi
fi
DEPLOY_TX_HASH="$(extract_deploy_field "${DEPLOY_OUTPUT}" tx_hash tx_id transaction_hash transaction_id)"
DEPLOY_TX_HASH_SOURCE="deploy_output"
if [[ -z "${DEPLOY_TX_HASH}" ]]; then
  DEPLOY_TX_HASH="$(program_deployment_tx_hash)"
  DEPLOY_TX_HASH_SOURCE="local_lez_program_deployment_transaction_hash"
fi
DEPLOY_TX_HASH_JSON="$(json_string_or_null "${DEPLOY_TX_HASH}")"
DEPLOY_WALLET_BIN="$(deploy_wallet_bin)"
DEPLOY_WALLET_HOME="$(deploy_wallet_home)"
DEPLOY_SIGNER_ACCOUNT="$(extract_deploy_field "${DEPLOY_OUTPUT}" signer deployer deployer_wallet account_id)"
DEPLOY_SIGNER_ACCOUNT_SOURCE="deploy_output"
if [[ -z "${DEPLOY_SIGNER_ACCOUNT}" ]]; then
  DEPLOY_SIGNER_ACCOUNT_SOURCE="missing_not_reported_by_deploy_command"
fi
DEPLOY_SIGNER_ACCOUNT_JSON="$(json_string_or_null "${DEPLOY_SIGNER_ACCOUNT}")"

cat > "${OUT_DIR}/deployment.json" <<JSON
{
  "status": "DEPLOY_TESTNET_OK",
  "mode": "testnet",
  "rpc_url": "${LEZ_RPC_URL}",
  "program_id": "${PROGRAM_ID}",
  "program_id_source": "${PROGRAM_ID_SOURCE}",
  "deploy_tx_hash": ${DEPLOY_TX_HASH_JSON},
  "deploy_tx_hash_source": "${DEPLOY_TX_HASH_SOURCE}",
  "deploy_wallet_bin": "${DEPLOY_WALLET_BIN}",
  "deploy_wallet_home": "${DEPLOY_WALLET_HOME}",
  "deploy_signer_account": ${DEPLOY_SIGNER_ACCOUNT_JSON},
  "deploy_signer_account_source": "${DEPLOY_SIGNER_ACCOUNT_SOURCE}",
  "program_image_id_hex": "${PROGRAM_IMAGE_ID_HEX}",
  "method_image_id_hex": "${METHOD_IMAGE_ID_HEX}",
  "idl": "${IDL}",
  "deploy_output_log": "${OUT_DIR}/deploy-output.log"
}
JSON

echo "DEPLOY_TESTNET_OK program_id=${PROGRAM_ID} deploy_tx_hash=${DEPLOY_TX_HASH:-missing} deploy_wallet_home=${DEPLOY_WALLET_HOME} metadata=${OUT_DIR}/deployment.json"
