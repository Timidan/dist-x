#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${APP_DIR}/.." && pwd)"

absolute_from_root() {
  local path="$1"
  if [[ -z "${path}" || "${path}" == /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s\n' "${ROOT_DIR}/${path}"
  fi
}

find_standalone_app() {
  if [[ -n "${LOGOS_STANDALONE_APP:-}" ]]; then
    printf '%s\n' "${LOGOS_STANDALONE_APP}"
    return
  fi
  if command -v logos-standalone-app >/dev/null 2>&1; then
    command -v logos-standalone-app
    return
  fi
  find /nix/store -maxdepth 4 -path '*/bin/logos-standalone-app' 2>/dev/null | sort | tail -n 1
}

APP_BIN="$(find_standalone_app)"
if [[ -z "${APP_BIN}" || ! -x "${APP_BIN}" ]]; then
  echo "logos-standalone-app not found. Set LOGOS_STANDALONE_APP." >&2
  exit 2
fi
MODULES_DIR="${DISTRIBUTIONX_MODULES_DIR:-/tmp/distributionx-modules-v2}"
CLIENT_LIB="${DISTRIBUTIONX_CLIENT_MODULE_LIB:-${ROOT_DIR}/distributionx_client_module/result/lib}"
if [[ -z "${DISTRIBUTIONX_CLI:-}" ]]; then
  if [[ ! -x "${ROOT_DIR}/target/debug/distributionx-cli" ]]; then
    (cd "${ROOT_DIR}" && cargo build -p distributionx-cli >/dev/null)
  fi
  export DISTRIBUTIONX_CLI="${ROOT_DIR}/target/debug/distributionx-cli"
fi

ARGS=("${APP_DIR}" "--width" "1120" "--height" "760")
if [[ -f "${CLIENT_LIB}/distributionx_client_plugin.so" ]]; then
  "${ROOT_DIR}/scripts/prepare-modules.sh" "${MODULES_DIR}" "${CLIENT_LIB}"
elif [[ -f "${MODULES_DIR}/distributionx_client_plugin.so" ]]; then
  "${ROOT_DIR}/scripts/prepare-modules.sh" "${MODULES_DIR}" "${MODULES_DIR}"
fi

if [[ -d "${MODULES_DIR}/distributionx_client" ]]; then
  ARGS+=("--modules-dir" "${MODULES_DIR}" "--load" "capability_module" "--load" "distributionx_client")
fi

if [[ "${DISTRIBUTIONX_DEV_UI:-0}" == "1" ]]; then
  ARGS+=("distributionx-dev-ui=1")
fi
if [[ "${DISTRIBUTIONX_DEBUG_UI:-0}" == "1" ]]; then
  ARGS+=("distributionx-debug-ui=1")
fi
if [[ -n "${DISTRIBUTIONX_CLAIM_LINK:-}" ]]; then
  ARGS+=("distributionx-claim-link=${DISTRIBUTIONX_CLAIM_LINK}")
fi
if [[ -n "${DISTRIBUTIONX_CLAIM_BUNDLE:-}" ]]; then
  ARGS+=("distributionx-claim-bundle=$(absolute_from_root "${DISTRIBUTIONX_CLAIM_BUNDLE}")")
fi

exec "${APP_BIN}" "${ARGS[@]}" "$@"
