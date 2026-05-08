#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${DISTRIBUTIONX_ENV_FILE:-${ROOT}/.env.local}"
USER_DIR="${DISTRIBUTIONX_BASECAMP_USER_DIR:-${ROOT}/target/basecamp-user}"
TMPDIR="${DISTRIBUTIONX_TMPDIR:-${ROOT}/target/tmp}"
export TMPDIR
PACKAGE=1
INSTALL=1
NO_LAUNCH=0
CLEAN_USER_DIR=0
RESET_LOCALNET=0
EXTRA_ARGS=()

usage() {
  cat <<'EOF'
Usage: scripts/start-basecamp.sh [options] [-- extra Basecamp args]

Packages DistributionX as LGX, installs the core module and UI app into an
isolated Basecamp user directory, loads .env.local, and launches Basecamp.

Options:
  --user-dir <dir>       Basecamp user dir. Default: target/basecamp-user.
  --basecamp-bin <path>  Basecamp binary. Or set LOGOS_BASECAMP_BIN.
  --no-package           Reuse target/lgx/*.lgx without rebuilding.
  --no-install           Do not install LGX packages before launch.
  --clean-user-dir       Delete the isolated user dir before install.
  --reset-localnet       Restart localhost sequencer with --clean and reset test state.
  --no-launch            Prepare/install, print the command, then exit.
  -h, --help             Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user-dir)
      USER_DIR="$2"
      shift 2
      ;;
    --basecamp-bin)
      LOGOS_BASECAMP_BIN="$2"
      shift 2
      ;;
    --no-package)
      PACKAGE=0
      shift
      ;;
    --no-install)
      INSTALL=0
      shift
      ;;
    --clean-user-dir)
      CLEAN_USER_DIR=1
      shift
      ;;
    --reset-localnet)
      RESET_LOCALNET=1
      shift
      ;;
    --no-launch)
      NO_LAUNCH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      EXTRA_ARGS+=("$@")
      break
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

log() {
  printf '[distributionx-basecamp] %s\n' "$*"
}

absolute_from_root() {
  local path="$1"
  if [[ -z "${path}" || "${path}" == /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s\n' "${ROOT}/${path}"
  fi
}

is_local_rpc() {
  local value="${LEZ_RPC_URL:-}"
  [[ "${value}" == http://127.0.0.1* ||
     "${value}" == http://localhost* ||
     "${value}" == http://[[]::1[]]* ]]
}

default_local_submit_hooks() {
  if ! is_local_rpc; then
    return
  fi
  export DISTRIBUTIONX_INIT_SUBMIT_COMMAND="${DISTRIBUTIONX_INIT_SUBMIT_COMMAND:-bash ${ROOT}/scripts/local-submit.sh init}"
  export DISTRIBUTIONX_FUND_SUBMIT_COMMAND="${DISTRIBUTIONX_FUND_SUBMIT_COMMAND:-bash ${ROOT}/scripts/local-submit.sh fund}"
  export DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND="${DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND:-bash ${ROOT}/scripts/local-submit.sh claim}"
  export DISTRIBUTIONX_CLOSE_SUBMIT_COMMAND="${DISTRIBUTIONX_CLOSE_SUBMIT_COMMAND:-bash ${ROOT}/scripts/local-submit.sh close}"
}

bootstrap_local_signer() {
  if ! is_local_rpc; then
    return
  fi
  export DISTRIBUTIONX_BOOTSTRAP_EVIDENCE_MODE="${DISTRIBUTIONX_BOOTSTRAP_EVIDENCE_MODE:-1}"
  export DISTRIBUTIONX_BOOTSTRAP_MIN_BALANCE="${DISTRIBUTIONX_BOOTSTRAP_MIN_BALANCE:-3000}"
  LEZ_DEPLOYER_WALLET="$(bash scripts/wallet-bootstrap.sh)"
  export LEZ_DEPLOYER_WALLET
}

reset_localnet_if_requested() {
  if [[ "${RESET_LOCALNET}" != "1" && "${DISTRIBUTIONX_BASECAMP_RESET_LOCALNET:-0}" != "1" ]]; then
    return
  fi
  if ! is_local_rpc; then
    echo "E_DISTRIBUTIONX_RESET_LOCALNET_REQUIRES_LOCAL_RPC: LEZ_RPC_URL=${LEZ_RPC_URL:-}" >&2
    exit 2
  fi
  log "Restarting local sequencer with clean state"
  bash scripts/standalone-sequencer.sh restart --clean
  log "Resetting DistributionX local test state"
  rm -rf "${DISTRIBUTIONX_STATE_DIR}"
  mkdir -p "${DISTRIBUTIONX_STATE_DIR}"
  if [[ -x "${ROOT}/scripts/install-reviewer-fixture.sh" && -d "${ROOT}/fixtures/reviewer-fast-path" ]]; then
    DISTRIBUTIONX_STATE_DIR="${DISTRIBUTIONX_STATE_DIR}" bash scripts/install-reviewer-fixture.sh >/dev/null
  fi
}

ensure_local_deployment() {
  if ! is_local_rpc; then
    return
  fi
  local deployment="${DISTRIBUTIONX_STATE_DIR}/deployment.json"
  if [[ -f "${deployment}" ]]; then
    return
  fi
  log "Preparing local DistributionX deployment metadata"
  bash scripts/deploy.sh --localnet
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
  if command -v LogosBasecamp >/dev/null 2>&1; then
    command -v LogosBasecamp
    return
  fi
  if command -v logos-basecamp >/dev/null 2>&1; then
    command -v logos-basecamp
    return
  fi
  find /nix/store -maxdepth 4 \( -path '*/bin/LogosBasecamp' -o -path '*/bin/.LogosBasecamp' \) 2>/dev/null | sort | tail -n 1
}

if [[ -r "${ENV_FILE}" ]]; then
  log "Loading ${ENV_FILE}"
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
elif [[ -n "${DISTRIBUTIONX_ENV_FILE:-}" ]]; then
  echo "E_DISTRIBUTIONX_ENV_FILE_NOT_FOUND: ${ENV_FILE}" >&2
  exit 2
fi

export RISC0_DEV_MODE=0
export QML_DISABLE_DISK_CACHE=1
export DISTRIBUTIONX_REPO_ROOT="${ROOT}"
log "RISC0_DEV_MODE=${RISC0_DEV_MODE}"

export DISTRIBUTIONX_STATE_DIR="${DISTRIBUTIONX_STATE_DIR:-${ROOT}/target/distributionx-testnet}"
if [[ -n "${DISTRIBUTIONX_STATE_DIR:-}" ]]; then
  export DISTRIBUTIONX_STATE_DIR="$(absolute_from_root "${DISTRIBUTIONX_STATE_DIR}")"
fi
if [[ -n "${DISTRIBUTIONX_ELIGIBILITY_CSV:-}" ]]; then
  export DISTRIBUTIONX_ELIGIBILITY_CSV="$(absolute_from_root "${DISTRIBUTIONX_ELIGIBILITY_CSV}")"
fi
if [[ -n "${DISTRIBUTIONX_DESTINATION_PACKET:-}" ]]; then
  export DISTRIBUTIONX_DESTINATION_PACKET="$(absolute_from_root "${DISTRIBUTIONX_DESTINATION_PACKET}")"
fi
if [[ -n "${DISTRIBUTIONX_CLAIM_BUNDLE:-}" ]]; then
  export DISTRIBUTIONX_CLAIM_BUNDLE="$(absolute_from_root "${DISTRIBUTIONX_CLAIM_BUNDLE}")"
fi
if [[ -n "${DISTRIBUTIONX_SERIALIZED_LEZ_TX:-}" ]]; then
  export DISTRIBUTIONX_SERIALIZED_LEZ_TX="$(absolute_from_root "${DISTRIBUTIONX_SERIALIZED_LEZ_TX}")"
fi
default_local_submit_hooks

BASECAMP_BIN="$(find_basecamp)"
if [[ -z "${BASECAMP_BIN}" || ! -x "${BASECAMP_BIN}" ]]; then
  echo "Basecamp binary not found. Set LOGOS_BASECAMP_BIN=/path/to/LogosBasecamp." >&2
  exit 2
fi

LGPM_BIN="${LGPM_BIN:-$(find_tool lgpm)}"
if [[ "${INSTALL}" -eq 1 && ( -z "${LGPM_BIN}" || ! -x "${LGPM_BIN}" ) ]]; then
  echo "lgpm binary not found. Build Basecamp or put lgpm on PATH." >&2
  exit 2
fi

cd "${ROOT}"

if [[ "${PACKAGE}" -eq 1 ]]; then
  bash scripts/package.sh
fi

reset_localnet_if_requested
bootstrap_local_signer
ensure_local_deployment

CORE_LGX="${ROOT}/target/lgx/distributionx-client.lgx"
UI_LGX="${ROOT}/target/lgx/DistributionX-ui.lgx"
if [[ ! -f "${CORE_LGX}" || ! -f "${UI_LGX}" ]]; then
  echo "LGX artifacts missing. Run scripts/package.sh first." >&2
  exit 2
fi

if [[ "${CLEAN_USER_DIR}" -eq 1 ]]; then
  rm -rf "${USER_DIR}"
fi
mkdir -p "${USER_DIR}/modules" "${USER_DIR}/plugins"
mkdir -p "${TMPDIR}"

if [[ "${INSTALL}" -eq 1 ]]; then
  log "Installing LGX packages into ${USER_DIR}"
  "${LGPM_BIN}" \
    --modules-dir "${USER_DIR}/modules" \
    --ui-plugins-dir "${USER_DIR}/plugins" \
    --allow-unsigned \
    install --file "${CORE_LGX}"
  "${LGPM_BIN}" \
    --modules-dir "${USER_DIR}/modules" \
    --ui-plugins-dir "${USER_DIR}/plugins" \
    --allow-unsigned \
    install --file "${UI_LGX}"
fi

APP_ARGS=()
if [[ -n "${LEZ_RPC_URL:-}" ]]; then
  APP_ARGS+=("distributionx-rpc=${LEZ_RPC_URL}")
fi
if [[ -n "${LEZ_DEPLOYER_WALLET:-}" ]]; then
  APP_ARGS+=("distributionx-distributor=${LEZ_DEPLOYER_WALLET}")
fi
if [[ -n "${DISTRIBUTIONX_AIRDROP_NAME:-}" ]]; then
  APP_ARGS+=("distributionx-airdrop=${DISTRIBUTIONX_AIRDROP_NAME}")
fi
if [[ -n "${DISTRIBUTIONX_STATE_DIR:-}" ]]; then
  APP_ARGS+=("distributionx-state-dir=${DISTRIBUTIONX_STATE_DIR}")
fi
if [[ -n "${DISTRIBUTIONX_TOKEN_ID:-}" ]]; then
  APP_ARGS+=("distributionx-token=${DISTRIBUTIONX_TOKEN_ID}")
fi
if [[ -n "${DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT:-}" ]]; then
  APP_ARGS+=("distributionx-token-source=${DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT}")
fi
if [[ -n "${DISTRIBUTIONX_RECOVERY_ADDRESS:-}" ]]; then
  APP_ARGS+=("distributionx-recovery=${DISTRIBUTIONX_RECOVERY_ADDRESS}")
fi
if [[ -n "${DISTRIBUTIONX_FUND_AMOUNT:-}" ]]; then
  APP_ARGS+=("distributionx-fund-amount=${DISTRIBUTIONX_FUND_AMOUNT}")
fi
if [[ -n "${DISTRIBUTIONX_EXPIRY_UNIX:-}" ]]; then
  APP_ARGS+=("distributionx-expiry-unix=${DISTRIBUTIONX_EXPIRY_UNIX}")
fi
if [[ -n "${DISTRIBUTIONX_ELIGIBILITY_CSV:-}" ]]; then
  APP_ARGS+=("distributionx-eligibility-csv=${DISTRIBUTIONX_ELIGIBILITY_CSV}")
fi
if [[ -n "${DISTRIBUTIONX_DESTINATION_PACKET:-}" ]]; then
  APP_ARGS+=("distributionx-destination-packet=${DISTRIBUTIONX_DESTINATION_PACKET}")
fi
if [[ -n "${DISTRIBUTIONX_CLAIM_LINK:-}" ]]; then
  APP_ARGS+=("distributionx-claim-link=${DISTRIBUTIONX_CLAIM_LINK}")
fi
if [[ -n "${DISTRIBUTIONX_CLAIM_BUNDLE:-}" ]]; then
  APP_ARGS+=("distributionx-claim-bundle=${DISTRIBUTIONX_CLAIM_BUNDLE}")
fi
if [[ -n "${DISTRIBUTIONX_RELAYER_URL:-}" ]]; then
  APP_ARGS+=("distributionx-relayer=${DISTRIBUTIONX_RELAYER_URL}")
fi
if [[ -n "${DISTRIBUTIONX_SERIALIZED_LEZ_TX:-}" ]]; then
  APP_ARGS+=("distributionx-serialized-lez-tx=${DISTRIBUTIONX_SERIALIZED_LEZ_TX}")
fi
if [[ -n "${DISTRIBUTIONX_INIT_SUBMIT_COMMAND:-}" ]]; then
  APP_ARGS+=("distributionx-init-submit-command-configured=1")
fi
if [[ -n "${DISTRIBUTIONX_FUND_SUBMIT_COMMAND:-}" ]]; then
  APP_ARGS+=("distributionx-fund-submit-command-configured=1")
fi
if [[ -n "${DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND:-}" ]]; then
  APP_ARGS+=("distributionx-claim-submit-command-configured=1")
fi
if [[ "${DISTRIBUTIONX_DEV_UI:-0}" == "1" ]]; then
  APP_ARGS+=("distributionx-dev-ui=1")
fi
if [[ "${DISTRIBUTIONX_DEBUG_UI:-0}" == "1" ]]; then
  APP_ARGS+=("distributionx-debug-ui=1")
fi

LAUNCH_CMD=("${BASECAMP_BIN}" "--user-dir" "${USER_DIR}" "${APP_ARGS[@]}" "${EXTRA_ARGS[@]}")

log "LEZ_RPC_URL=${LEZ_RPC_URL:-}"
log "LEZ_DEPLOYER_WALLET=${LEZ_DEPLOYER_WALLET:-}"
printf '[distributionx-basecamp] Command:'
printf ' %q' "${LAUNCH_CMD[@]}"
printf '\n'

if [[ "${NO_LAUNCH}" -eq 1 ]]; then
  exit 0
fi

exec "${LAUNCH_CMD[@]}"
