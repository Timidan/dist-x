#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LGX_DIR="${DISTRIBUTIONX_LGX_DIR:-${ROOT}/target/lgx}"
NIX_STORE_ROOT="${DISTRIBUTIONX_NIX_STORE_ROOT:-/nix/store}"
SMOKE_DIR="${DISTRIBUTIONX_LGX_SMOKE_DIR:-}"
OWNS_SMOKE_DIR=0
APP_PID=""
HOST_PID=""

find_tool() {
  local name="$1"
  if command -v "${name}" >/dev/null 2>&1; then
    command -v "${name}"
    return
  fi
  find "${NIX_STORE_ROOT}" -maxdepth 4 -path "*/bin/${name}" 2>/dev/null \
    | sort | tail -n 1
}

stop_app() {
  [[ -n "${APP_PID}" ]] || return 0
  if kill -0 "${APP_PID}" 2>/dev/null; then
    kill -TERM "${APP_PID}" 2>/dev/null || true
    for _ in $(seq 1 40); do
      kill -0 "${APP_PID}" 2>/dev/null || break
      sleep 0.25
    done
  fi
  if kill -0 "${APP_PID}" 2>/dev/null; then
    kill -KILL "${APP_PID}" 2>/dev/null || true
  fi
  wait "${APP_PID}" 2>/dev/null || true
  APP_PID=""
}

cleanup() {
  stop_app
  if [[ "${OWNS_SMOKE_DIR}" == "1" && -n "${SMOKE_DIR}" && -d "${SMOKE_DIR}" ]]; then
    rm -rf -- "${SMOKE_DIR}"
  fi
}
trap cleanup EXIT INT TERM

LGPM_BIN="${LGPM_BIN:-$(find_tool lgpm)}"
STANDALONE_BIN="${LOGOS_STANDALONE_APP_BIN:-$(find_tool logos-standalone-app)}"
NODE_BIN="${NODE_BIN:-$(find_tool node)}"
CORE_LGX="${LGX_DIR}/distributionx-client.lgx"
UI_LGX="${LGX_DIR}/DistributionX-ui.lgx"
LOAD_PROBE="${ROOT}/scripts/lgx-load-probe.mjs"

[[ -x "${LGPM_BIN}" ]] || {
  echo "E_DISTRIBUTIONX_LGPM_NOT_FOUND" >&2
  exit 2
}
[[ -x "${STANDALONE_BIN}" ]] || {
  echo "E_DISTRIBUTIONX_STANDALONE_APP_NOT_FOUND" >&2
  exit 2
}
[[ -x "${NODE_BIN}" && -s "${LOAD_PROBE}" ]] || {
  echo "E_DISTRIBUTIONX_LGX_LOAD_PROBE_NOT_FOUND" >&2
  exit 2
}
[[ -s "${CORE_LGX}" && -s "${UI_LGX}" ]] || {
  echo "E_DISTRIBUTIONX_LGX_MISSING" >&2
  exit 2
}

umask 077
if [[ -z "${SMOKE_DIR}" ]]; then
  SMOKE_DIR="$(mktemp -d)"
  OWNS_SMOKE_DIR=1
fi
mkdir -p \
  "${SMOKE_DIR}/home" \
  "${SMOKE_DIR}/modules" \
  "${SMOKE_DIR}/plugins" \
  "${SMOKE_DIR}/runtime" \
  "${SMOKE_DIR}/state" \
  "${SMOKE_DIR}/tmp"
chmod 0700 "${SMOKE_DIR}" "${SMOKE_DIR}/runtime"

env HOME="${SMOKE_DIR}/home" "${LGPM_BIN}" \
  --modules-dir "${SMOKE_DIR}/modules" \
  --ui-plugins-dir "${SMOKE_DIR}/plugins" \
  --allow-unsigned \
  install --file "${CORE_LGX}" >/dev/null
env HOME="${SMOKE_DIR}/home" "${LGPM_BIN}" \
  --modules-dir "${SMOKE_DIR}/modules" \
  --ui-plugins-dir "${SMOKE_DIR}/plugins" \
  --allow-unsigned \
  install --file "${UI_LGX}" >/dev/null

CORE_PLUGIN="${SMOKE_DIR}/modules/distributionx_client/distributionx_client_plugin.so"
CORE_CLI="${SMOKE_DIR}/modules/distributionx_client/distributionx-cli"
UI_PLUGIN="${SMOKE_DIR}/plugins/distributionx"
[[ -s "${CORE_PLUGIN}" && -x "${CORE_CLI}" && -s "${UI_PLUGIN}/manifest.json" ]] || {
  echo "E_DISTRIBUTIONX_LGX_INSTALL_INCOMPLETE" >&2
  exit 1
}

LOAD_LOG="${SMOKE_DIR}/load.log"
if bash -c 'exec 3<>/dev/tcp/127.0.0.1/3768' 2>/dev/null; then
  echo "E_DISTRIBUTIONX_LGX_INSPECTOR_PORT_IN_USE" >&2
  exit 2
fi
(
  cd "${SMOKE_DIR}"
  exec env -i \
    HOME="${SMOKE_DIR}/home" \
    LANG=C.UTF-8 \
    PATH="${PATH}" \
    QT_QPA_PLATFORM=offscreen \
    RISC0_DEV_MODE=0 \
    TMPDIR="${SMOKE_DIR}/tmp" \
    XDG_RUNTIME_DIR="${SMOKE_DIR}/runtime" \
    DISTRIBUTIONX_CLI="${CORE_CLI}" \
    DISTRIBUTIONX_STATE_DIR="${SMOKE_DIR}/state" \
    "${STANDALONE_BIN}" \
      --modules-dir "${SMOKE_DIR}/modules" \
      --load distributionx_client \
      "${UI_PLUGIN}"
) >"${LOAD_LOG}" 2>&1 &
APP_PID=$!

host_ready=0
for _ in $(seq 1 120); do
  if ! kill -0 "${APP_PID}" 2>/dev/null; then
    echo "E_DISTRIBUTIONX_INSTALLED_LGX_LOAD_EXITED" >&2
    tail -n 80 "${LOAD_LOG}" >&2
    exit 1
  fi
  HOST_PID="$(pgrep -P "${APP_PID}" -f 'logos_host.*--name distributionx_client' | head -n 1 || true)"
  if [[ -n "${HOST_PID}" ]] && kill -0 "${HOST_PID}" 2>/dev/null; then
    host_ready=1
    break
  fi
  sleep 0.25
done

if [[ "${host_ready}" != "1" ]]; then
  echo "E_DISTRIBUTIONX_INSTALLED_LGX_HOST_TIMEOUT" >&2
  tail -n 80 "${LOAD_LOG}" >&2
  exit 1
fi

inspector_ready=0
for _ in $(seq 1 120); do
  if ! kill -0 "${APP_PID}" 2>/dev/null || ! kill -0 "${HOST_PID}" 2>/dev/null; then
    echo "E_DISTRIBUTIONX_INSTALLED_LGX_LOAD_EXITED_BEFORE_API_READY" >&2
    tail -n 80 "${LOAD_LOG}" >&2
    exit 1
  fi
  if bash -c 'exec 3<>/dev/tcp/127.0.0.1/3768' 2>/dev/null; then
    inspector_ready=1
    break
  fi
  sleep 0.25
done

if [[ "${inspector_ready}" != "1" ]]; then
  echo "E_DISTRIBUTIONX_INSTALLED_LGX_INSPECTOR_TIMEOUT" >&2
  tail -n 80 "${LOAD_LOG}" >&2
  exit 1
fi

PROBE_LOG="${SMOKE_DIR}/probe.log"
if ! env \
  QML_INSPECTOR_HOST=127.0.0.1 \
  QML_INSPECTOR_PORT=3768 \
  QT_QPA_PLATFORM=offscreen \
  "${NODE_BIN}" "${LOAD_PROBE}" >"${PROBE_LOG}" 2>&1; then
  echo "E_DISTRIBUTIONX_INSTALLED_LGX_API_NOT_READY" >&2
  tail -n 80 "${PROBE_LOG}" >&2
  tail -n 80 "${LOAD_LOG}" >&2
  exit 1
fi

stability_seconds="${DISTRIBUTIONX_LGX_LOAD_STABILITY_SECONDS:-3}"
[[ "${stability_seconds}" =~ ^[0-9]+$ ]] || {
  echo "E_DISTRIBUTIONX_LGX_LOAD_STABILITY_SECONDS" >&2
  exit 2
}
sleep "${stability_seconds}"
if ! kill -0 "${APP_PID}" 2>/dev/null || ! kill -0 "${HOST_PID}" 2>/dev/null; then
  echo "E_DISTRIBUTIONX_INSTALLED_LGX_LOAD_NOT_STABLE" >&2
  tail -n 80 "${LOAD_LOG}" >&2
  exit 1
fi

echo "DISTRIBUTIONX_INSTALLED_LGX_LOAD_OK api=listAirdrops stability_seconds=${stability_seconds}"
