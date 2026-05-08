#!/usr/bin/env bash
set -euo pipefail

# Build and run the LEZ sequencer_service with its `standalone` feature.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UID_VAL="${UID:-$(id -u)}"

ENV_FILE="${DISTRIBUTIONX_ENV_FILE:-${ROOT}/.env.local}"
if [[ -r "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
fi

LEZ_REPO="${DISTRIBUTIONX_LEZ_REPO:-${ROOT}/.scaffold/cache/repos/lez/35d8df0d031315219f94d1546ceb862b0e5b208f}"
BASE_CONFIG="${LEZ_REPO}/sequencer/service/configs/debug/sequencer_config.json"
TARGET_DIR="${DISTRIBUTIONX_STANDALONE_TARGET_DIR:-${ROOT}/target/lez-standalone}"
STATE_DIR="${DISTRIBUTIONX_STANDALONE_STATE_DIR:-${ROOT}/target/lez-standalone-state}"
RUNTIME_CONFIG="/tmp/distributionx-standalone-sequencer-${UID_VAL}.json"
PID_FILE="/tmp/distributionx-standalone-sequencer-${UID_VAL}.pid"
LOG_FILE="/tmp/distributionx-standalone-sequencer-${UID_VAL}.log"
PORT="${SEQUENCER_RPC_PORT:-3040}"
MAX_BLOCK_SIZE="${DISTRIBUTIONX_SEQUENCER_MAX_BLOCK_SIZE:-4 MiB}"
PUBLIC_EXECUTION_CYCLE_LIMIT="${DISTRIBUTIONX_PUBLIC_EXECUTION_CYCLE_LIMIT:-268435456}"

log() { printf '[standalone-sequencer] %s\n' "$*"; }
die() { printf '[standalone-sequencer] ERROR: %s\n' "$*" >&2; exit 1; }

pid_alive() {
  local pid="${1:-}"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" 2>/dev/null || return 1
}

port_up() {
  bash -c ">/dev/tcp/127.0.0.1/${PORT}" 2>/dev/null
}

port_listener_pid() {
  ss -tlnp "sport = :${PORT}" 2>/dev/null \
    | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' \
    | head -1
}

write_runtime_config() {
  mkdir -p "${STATE_DIR}"
  python3 - "${BASE_CONFIG}" "${RUNTIME_CONFIG}" "${STATE_DIR}" "${MAX_BLOCK_SIZE}" <<'PY'
import json
import sys

source, dest, home, max_block_size = sys.argv[1:]
with open(source, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data["home"] = home
data["max_block_size"] = max_block_size
if "initial_accounts" in data and "initial_public_accounts" not in data:
    data["initial_public_accounts"] = data["initial_accounts"]
with open(dest, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
}

build_binary() {
  [[ -d "${LEZ_REPO}" ]] || die "LEZ repo not found: ${LEZ_REPO}. Run lgs setup first."
  patch_public_execution_cycle_limit
  patch_cycle_logging
  patch_stable_duration_constructors
  CARGO_TARGET_DIR="${TARGET_DIR}" \
    cargo build --release -p sequencer_service --features standalone \
    --manifest-path "${LEZ_REPO}/Cargo.toml"
}

patch_public_execution_cycle_limit() {
  [[ "${PUBLIC_EXECUTION_CYCLE_LIMIT}" =~ ^[0-9]+$ ]] \
    || die "DISTRIBUTIONX_PUBLIC_EXECUTION_CYCLE_LIMIT must be an integer"
  local file="${LEZ_REPO}/nssa/src/program.rs"
  [[ -f "${file}" ]] || die "nssa program source not found: ${file}"
  perl -0pi \
    -e "s#const MAX_NUM_CYCLES_PUBLIC_EXECUTION: u64 = [^;]+;[^\\n]*#const MAX_NUM_CYCLES_PUBLIC_EXECUTION: u64 = ${PUBLIC_EXECUTION_CYCLE_LIMIT}; // patched by DistributionX standalone helper#g" \
    "${file}"
}

patch_cycle_logging() {
  local public_file="${LEZ_REPO}/nssa/src/program.rs"
  [[ -f "${public_file}" ]] || die "nssa program source not found: ${public_file}"

  python3 - "${public_file}" <<'PY'
from pathlib import Path
import sys

public_file = Path(sys.argv[1])

public_text = public_file.read_text()
if "DISTRIBUTIONX_LEZ_CU kind=public" not in public_text:
    needle = """        let session_info = executor
            .execute(env, self.elf())
            .map_err(|e| NssaError::ProgramExecutionFailed(e.to_string()))?;

        // Get outputs
"""
    replacement = """        let session_info = executor
            .execute(env, self.elf())
            .map_err(|e| NssaError::ProgramExecutionFailed(e.to_string()))?;
        let program_id_hex: String = self
            .id
            .iter()
            .flat_map(|word| word.to_le_bytes())
            .map(|byte| format!("{byte:02x}"))
            .collect();
        eprintln!(
            "DISTRIBUTIONX_LEZ_CU kind=public program_id={} cycles={}",
            program_id_hex,
            session_info.cycles()
        );

        // Get outputs
"""
    if needle not in public_text:
        raise SystemExit(f"public cycle insertion point not found in {public_file}")
    public_file.write_text(public_text.replace(needle, replacement))
PY
}

patch_stable_duration_constructors() {
  local files=()
  while IFS= read -r file; do
    files+=("${file}")
  done < <(rg -l 'Duration::from_(mins|hours)\([0-9]+' "${LEZ_REPO}" \
      --glob '*.rs' --glob '!target/**' 2>/dev/null || true)

  [[ "${#files[@]}" -gt 0 ]] || return 0

  log "patching unstable Duration::from_mins/from_hours calls for stable Rust"
  perl -0pi \
    -e 's/Duration::from_mins\(([0-9]+)\)/Duration::from_secs($1 * 60)/g;' \
    -e 's/Duration::from_hours\(([0-9]+)\)/Duration::from_secs($1 * 60 * 60)/g;' \
    "${files[@]}"
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
    rm -rf "${STATE_DIR}"
  fi

  build_binary
  write_runtime_config

  rm -f "${LOG_FILE}"
  nohup setsid env RUST_LOG="${RUST_LOG:-info}" \
    "${TARGET_DIR}/release/sequencer_service" "${RUNTIME_CONFIG}" --port "${PORT}" \
    > "${LOG_FILE}" 2>&1 < /dev/null &
  local pid=$!
  disown "${pid}" 2>/dev/null || true
  printf '%s\n' "${pid}" > "${PID_FILE}"

  for _ in $(seq 1 "${DISTRIBUTIONX_LOCALNET_READY_ATTEMPTS:-60}"); do
    if port_up; then
      log "ready rpc=http://127.0.0.1:${PORT} pid=${pid} log=${LOG_FILE}"
      return
    fi
    if ! pid_alive "${pid}"; then
      cat "${LOG_FILE}" >&2 || true
      die "sequencer exited before RPC became ready"
    fi
    sleep 1
  done
  cat "${LOG_FILE}" >&2 || true
  die "sequencer did not become ready on ${PORT}"
}

cmd_stop() {
  local pid=""
  [[ -f "${PID_FILE}" ]] && pid="$(cat "${PID_FILE}")"
  if pid_alive "${pid}"; then
    log "stopping pid=${pid}"
    kill "${pid}" 2>/dev/null || true
    sleep 1
  else
    log "not running"
  fi
  rm -f "${PID_FILE}"
}

cmd_status() {
  local pid=""
  [[ -f "${PID_FILE}" ]] && pid="$(cat "${PID_FILE}")"
  if pid_alive "${pid}"; then
    printf 'Sequencer : running (pid=%s)\n' "${pid}"
  else
    printf 'Sequencer : stopped\n'
  fi
  if port_up; then
    printf 'RPC :%-5s : reachable\n' "${PORT}"
  else
    printf 'RPC :%-5s : unreachable\n' "${PORT}"
  fi
  printf 'Log       : %s\n' "${LOG_FILE}"
}

case "${1:-}" in
  start) shift; cmd_start "$@" ;;
  stop) cmd_stop ;;
  restart) shift; cmd_stop; cmd_start "$@" ;;
  status) cmd_status ;;
  *)
    cat <<'EOF'
Usage: scripts/standalone-sequencer.sh <command> [options]

Commands:
  start [--clean]   Build and start standalone sequencer_service.
  stop              Stop the managed standalone sequencer.
  restart [--clean] Stop then start.
  status            Show process/RPC state.
EOF
    exit 64
    ;;
esac
