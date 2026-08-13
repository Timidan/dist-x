#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

ENV_FILE="${DISTRIBUTIONX_ENV_FILE:-${ROOT}/.env.local}"
CHECK_RPC=1
CHECK_BASECAMP=1
CHECK_WALLET=1

usage() {
  cat <<'EOF'
Usage: scripts/preflight.sh [options]

Checks the clean-machine requirements before packaging, Basecamp testing, or
starting a real Risc0 proof.

Options:
  --no-rpc        Skip LEZ_RPC_URL reachability check.
  --no-basecamp   Skip LogosBasecamp/lgx/lgpm checks.
  --no-wallet     Skip LEZ wallet storage check.
  -h, --help      Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-rpc)
      CHECK_RPC=0
      shift
      ;;
    --no-basecamp)
      CHECK_BASECAMP=0
      shift
      ;;
    --no-wallet)
      CHECK_WALLET=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -r "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
elif [[ -n "${DISTRIBUTIONX_ENV_FILE:-}" ]]; then
  echo "E_DISTRIBUTIONX_ENV_FILE_NOT_FOUND: ${ENV_FILE}" >&2
  exit 2
fi

failures=0

ok() {
  printf 'OK %s\n' "$*"
}

fail() {
  printf 'FAIL %s\n' "$*" >&2
  failures=$((failures + 1))
}

find_tool() {
  local name="$1"
  if command -v "${name}" >/dev/null 2>&1; then
    command -v "${name}"
    return
  fi
  find /nix/store -maxdepth 4 -path "*/bin/${name}" 2>/dev/null | sort | tail -n 1
}

find_basecamp() {
  local candidate
  for candidate in \
    "${LOGOS_BASECAMP_BIN:-}" \
    "${LOGOS_BASECAMP_APP:-}" \
    "${ROOT}/../logos-basecamp/result/bin/LogosBasecamp" \
    "${ROOT}/../logos-basecamp/result/bin/.LogosBasecamp"; do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return
    fi
  done
  find_tool LogosBasecamp
}

require_command() {
  local name="$1"
  if command -v "${name}" >/dev/null 2>&1; then
    ok "${name}: $(command -v "${name}")"
  else
    fail "${name} is not on PATH"
  fi
}

require_command cargo
require_command git
require_command nix
require_command curl

if [[ "${RISC0_DEV_MODE:-0}" == "1" ]]; then
  fail "RISC0_DEV_MODE=1; final proof/demo must use RISC0_DEV_MODE=0"
else
  ok "RISC0_DEV_MODE=${RISC0_DEV_MODE:-0}"
fi

if [[ "${CHECK_BASECAMP}" == "1" ]]; then
  LGX_BIN="${LGX_BIN:-$(find_tool lgx)}"
  LGPM_BIN="${LGPM_BIN:-$(find_tool lgpm)}"
  BASECAMP_BIN="$(find_basecamp)"
  [[ -n "${LGX_BIN}" && -x "${LGX_BIN}" ]] && ok "lgx: ${LGX_BIN}" || fail "lgx not found; build Basecamp or put lgx on PATH"
  [[ -n "${LGPM_BIN}" && -x "${LGPM_BIN}" ]] && ok "lgpm: ${LGPM_BIN}" || fail "lgpm not found; build Basecamp or put lgpm on PATH"
  [[ -n "${BASECAMP_BIN}" && -x "${BASECAMP_BIN}" ]] && ok "Basecamp: ${BASECAMP_BIN}" || fail "LogosBasecamp not found; set LOGOS_BASECAMP_BIN"
fi

if [[ "${CHECK_RPC}" == "1" ]]; then
  if [[ -z "${LEZ_RPC_URL:-}" ]]; then
    fail "LEZ_RPC_URL is not set"
  else
    if bash "${ROOT}/scripts/lez-fingerprint.sh" --rpc "${LEZ_RPC_URL}" >/dev/null 2>&1; then
      ok "LEZ_RPC_URL healthy with compatible built-ins: ${LEZ_RPC_URL}"
    else
      fail "LEZ_RPC_URL not reachable: ${LEZ_RPC_URL}"
    fi
  fi
fi

for hook in \
  DISTRIBUTIONX_INIT_SUBMIT_COMMAND \
  DISTRIBUTIONX_FUND_SUBMIT_COMMAND \
  DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND; do
  if [[ -n "${!hook:-}" ]]; then
    ok "${hook} configured"
  else
    fail "${hook} is required for real chain transactions"
  fi
done

if [[ "${CHECK_WALLET}" == "1" ]]; then
  WALLET_HOME="${LEE_WALLET_HOME_DIR:-}"
  if [[ -z "${WALLET_HOME}" ]]; then
    WALLET_HOME="${ROOT}/target/lez-v0.2.4-wallet"
  fi
  if [[ -f "${WALLET_HOME}/storage.json" ]]; then
    ok "LEZ wallet storage: ${WALLET_HOME}/storage.json"
  else
    fail "LEZ wallet storage missing: ${WALLET_HOME}/storage.json"
  fi
  if [[ -n "${LEZ_DEPLOYER_WALLET:-}" ]]; then
    ok "LEZ_DEPLOYER_WALLET=${LEZ_DEPLOYER_WALLET}"
  else
    fail "LEZ_DEPLOYER_WALLET is not set"
  fi
fi

if cargo +1.94.0 run -q --release -p distributionx-cli -- method-id >/tmp/distributionx-preflight-method-id.json; then
  ok "distributionx-cli release method-id"
else
  fail "distributionx-cli release build/method-id failed"
fi

if [[ "${failures}" -gt 0 ]]; then
  echo "E_DISTRIBUTIONX_PREFLIGHT_FAILED: ${failures} check(s) failed" >&2
  exit 1
fi

echo "DISTRIBUTIONX_PREFLIGHT_OK"
