#!/usr/bin/env bash
set -euo pipefail

# Build and run the exact LEZ v0.2.4 standalone sequencer on loopback.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UID_VAL="${UID:-$(id -u)}"
LEZ_COMMIT=""

ENV_FILE="${DISTRIBUTIONX_ENV_FILE:-${ROOT}/.env.local}"
if [[ -r "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
fi

LEZ_REPO="${DISTRIBUTIONX_LEZ_REPO:-${ROOT}/.scaffold/cache/repos/lez/v0.2.4}"
BASE_CONFIG="${LEZ_REPO}/lez/sequencer/service/configs/debug/sequencer_config.json"
TARGET_DIR="${DISTRIBUTIONX_STANDALONE_TARGET_DIR:-${ROOT}/target/lez-v0.2.4-build}"
STATE_DIR="${DISTRIBUTIONX_STANDALONE_STATE_DIR:-${ROOT}/target/lez-v0.2.4-standalone-state}"
CARGO_HOME_DIR="${CARGO_HOME:-${ROOT}/target/cargo-home}"
RUNTIME_CONFIG="/tmp/distributionx-standalone-sequencer-${UID_VAL}.json"
PID_FILE="/tmp/distributionx-standalone-sequencer-${UID_VAL}.pid"
LOG_FILE="/tmp/distributionx-standalone-sequencer-${UID_VAL}.log"
PORT="${SEQUENCER_RPC_PORT:-3040}"
METRICS_PORT="${DISTRIBUTIONX_SEQUENCER_METRICS_PORT:-9000}"
MAX_BLOCK_SIZE="${DISTRIBUTIONX_SEQUENCER_MAX_BLOCK_SIZE:-4 MiB}"
BLOCK_CREATE_TIMEOUT="${DISTRIBUTIONX_SEQUENCER_BLOCK_CREATE_TIMEOUT:-5s}"
RPC_URL="http://127.0.0.1:${PORT}"
DEBUG_CHANNEL_ID="$(printf '01%.0s' {1..32})"

log() { printf '[standalone-sequencer] %s\n' "$*"; }
die() { printf '[standalone-sequencer] ERROR: %s\n' "$*" >&2; exit 1; }

pid_alive() {
  local pid="${1:-}"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

port_up() {
  bash -c ">/dev/tcp/127.0.0.1/${PORT}" 2>/dev/null
}

port_listener_pid() {
  ss -tlnp "sport = :${PORT}" 2>/dev/null \
    | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' \
    | head -1
}

validate_checkout() {
  LEZ_COMMIT="$(bash "${ROOT}/scripts/lez-source-guard.sh" "${LEZ_REPO}")" \
    || die "LEZ source validation failed"
  [[ -f "${BASE_CONFIG}" ]] || die "sequencer config not found: ${BASE_CONFIG}"
}

validate_runtime() {
  command -v rustup >/dev/null 2>&1 || die "rustup is required"
  rustup run 1.94.0 rustc --version >/dev/null 2>&1 \
    || die "Rust 1.94.0 is required; run: rustup toolchain install 1.94.0"

  if [[ -z "${RISC0_SERVER_PATH:-}" ]]; then
    RISC0_SERVER_PATH="$(command -v r0vm || true)"
  fi
  [[ -x "${RISC0_SERVER_PATH:-}" ]] \
    || die "r0vm is required; install the Risc0 3.0.5 toolchain"
  "${RISC0_SERVER_PATH}" --version 2>/dev/null | grep -q '3\.0\.5' \
    || die "r0vm 3.0.5 is required: ${RISC0_SERVER_PATH}"
  export RISC0_SERVER_PATH
}

validate_clean_target() {
  local resolved_root resolved_state
  resolved_root="$(realpath -m "${ROOT}/target")"
  resolved_state="$(realpath -m "${STATE_DIR}")"
  [[ "${resolved_state}" == "${resolved_root}/"* ]] \
    || die "refusing --clean outside ${resolved_root}: ${resolved_state}"
  [[ "${resolved_state}" != "${resolved_root}" ]] \
    || die "refusing to clean the whole target directory"
}

write_runtime_config() {
  mkdir -p "${STATE_DIR}"
  python3 - "${BASE_CONFIG}" "${RUNTIME_CONFIG}" "${STATE_DIR}" \
    "${MAX_BLOCK_SIZE}" "${BLOCK_CREATE_TIMEOUT}" <<'PY'
import json
import sys

source, dest, home, max_block_size, block_create_timeout = sys.argv[1:]
with open(source, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data["home"] = home
data["max_block_size"] = max_block_size
data["block_create_timeout"] = block_create_timeout
with open(dest, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
}

build_binaries() {
  validate_checkout
  validate_runtime
  mkdir -p "${CARGO_HOME_DIR}" "${TARGET_DIR}"
  log "building LEZ ${LEZ_COMMIT} standalone sequencer"
  CARGO_HOME="${CARGO_HOME_DIR}" CARGO_TARGET_DIR="${TARGET_DIR}" \
    cargo +1.94.0 build --locked --release \
      --manifest-path "${LEZ_REPO}/Cargo.toml" \
      -p sequencer_service --features standalone
  log "building matching LEZ wallet"
  CARGO_HOME="${CARGO_HOME_DIR}" CARGO_TARGET_DIR="${TARGET_DIR}" \
    cargo +1.94.0 build --locked --release \
      --manifest-path "${LEZ_REPO}/Cargo.toml" -p wallet
}

wait_for_ready() {
  local pid="$1"
  for _ in $(seq 1 "${DISTRIBUTIONX_LOCALNET_READY_ATTEMPTS:-90}"); do
    if bash "${ROOT}/scripts/lez-fingerprint.sh" --rpc "${RPC_URL}" \
      --expected-channel "${DEBUG_CHANNEL_ID}" >/dev/null 2>&1; then
      bash "${ROOT}/scripts/lez-fingerprint.sh" --rpc "${RPC_URL}" \
        --expected-channel "${DEBUG_CHANNEL_ID}"
      return 0
    fi
    if ! pid_alive "${pid}"; then
      cat "${LOG_FILE}" >&2 || true
      die "sequencer exited before its RPC fingerprint was ready"
    fi
    sleep 1
  done
  cat "${LOG_FILE}" >&2 || true
  die "sequencer did not become ready on ${RPC_URL}"
}

cmd_start() {
  local clean=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --clean) clean=1; shift ;;
      *) die "unknown option: $1" ;;
    esac
  done

  if port_up; then
    die "port ${PORT} already in use by pid=$(port_listener_pid)"
  fi
  if [[ "${clean}" -eq 1 ]]; then
    validate_clean_target
    rm -rf -- "${STATE_DIR}"
  fi

  build_binaries
  write_runtime_config
  rm -f -- "${LOG_FILE}"

  nohup setsid env \
    RUST_LOG="${DISTRIBUTIONX_SEQUENCER_RUST_LOG:-info}" \
    RISC0_DEV_MODE=0 \
    RISC0_EXECUTOR=ipc \
    RISC0_SERVER_PATH="${RISC0_SERVER_PATH}" \
    "${TARGET_DIR}/release/sequencer_service" \
      "${RUNTIME_CONFIG}" \
      --listen-address 127.0.0.1 \
      --port "${PORT}" \
      --home "${STATE_DIR}" \
      --metrics-address "127.0.0.1:${METRICS_PORT}" \
    > "${LOG_FILE}" 2>&1 < /dev/null &
  local pid=$!
  disown "${pid}" 2>/dev/null || true
  printf '%s\n' "${pid}" > "${PID_FILE}"

  wait_for_ready "${pid}"
  log "ready rpc=${RPC_URL} pid=${pid} log=${LOG_FILE}"
}

cmd_stop() {
  local pid=""
  [[ -f "${PID_FILE}" ]] && pid="$(cat "${PID_FILE}")"
  if ! pid_alive "${pid}"; then
    log "not running"
    rm -f -- "${PID_FILE}"
    return
  fi

  log "stopping pid=${pid}"
  kill -TERM "${pid}" 2>/dev/null || true
  for _ in $(seq 1 30); do
    if ! pid_alive "${pid}"; then
      wait "${pid}" 2>/dev/null || true
      rm -f -- "${PID_FILE}"
      if grep -Fq 'Sequencer shutdown complete' "${LOG_FILE}" 2>/dev/null; then
        log "stopped cleanly"
        return
      fi
      die "sequencer exited without the graceful-shutdown marker; inspect ${LOG_FILE}"
    fi
    sleep 1
  done
  kill -KILL "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true
  rm -f -- "${PID_FILE}"
  die "sequencer did not stop within 30 seconds and was killed"
}

cmd_status() {
  local pid=""
  [[ -f "${PID_FILE}" ]] && pid="$(cat "${PID_FILE}")"
  if pid_alive "${pid}"; then
    printf 'Sequencer : running (pid=%s)\n' "${pid}"
  else
    printf 'Sequencer : stopped\n'
  fi
  if bash "${ROOT}/scripts/lez-fingerprint.sh" --rpc "${RPC_URL}" \
    --expected-channel "${DEBUG_CHANNEL_ID}" >/dev/null 2>&1; then
    printf 'RPC       : compatible (%s)\n' "${RPC_URL}"
  else
    printf 'RPC       : unavailable or incompatible (%s)\n' "${RPC_URL}"
  fi
  printf 'LEZ commit: %s\n' "${LEZ_COMMIT}"
  printf 'Log       : %s\n' "${LOG_FILE}"
}

case "${1:-}" in
  build) build_binaries ;;
  start) shift; cmd_start "$@" ;;
  stop) cmd_stop ;;
  restart) shift; cmd_stop; cmd_start "$@" ;;
  status) cmd_status ;;
  *)
    cat <<'EOF'
Usage: scripts/standalone-sequencer.sh <command> [options]

Commands:
  build             Build the pinned sequencer and wallet.
  start [--clean]   Start a loopback-only standalone sequencer.
  stop              Stop gracefully (30-second limit).
  restart [--clean] Stop, then start.
  status            Show process/RPC compatibility state.
EOF
    exit 64
    ;;
esac
