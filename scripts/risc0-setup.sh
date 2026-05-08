#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[distributionx-risc0] %s\n' "$*"
}

find_rzup() {
  if command -v rzup >/dev/null 2>&1; then
    command -v rzup
    return
  fi
  if [[ -x "${HOME}/.risc0/bin/rzup" ]]; then
    printf '%s\n' "${HOME}/.risc0/bin/rzup"
    return
  fi
}

RZUP_BIN="$(find_rzup || true)"
if [[ -z "${RZUP_BIN}" ]]; then
  if [[ "${DISTRIBUTIONX_RISC0_AUTO_INSTALL:-1}" != "1" ]]; then
    echo "E_RISC0_RZUP_MISSING: install rzup or set DISTRIBUTIONX_RISC0_AUTO_INSTALL=1" >&2
    exit 2
  fi
  log "Installing rzup"
  curl -L https://risczero.com/install | bash
  RZUP_BIN="${HOME}/.risc0/bin/rzup"
fi

if [[ ! -x "${RZUP_BIN}" ]]; then
  echo "E_RISC0_RZUP_NOT_EXECUTABLE: ${RZUP_BIN}" >&2
  exit 2
fi

export PATH="$(dirname "${RZUP_BIN}"):${PATH}"
if [[ -n "${GITHUB_PATH:-}" ]]; then
  dirname "${RZUP_BIN}" >> "${GITHUB_PATH}"
fi

log "Using ${RZUP_BIN}"
"${RZUP_BIN}" install rust
"${RZUP_BIN}" install cpp
"${RZUP_BIN}" install cargo-risczero
"${RZUP_BIN}" install r0vm
"${RZUP_BIN}" show

if ! find "${RISC0_HOME:-${HOME}/.risc0}/toolchains" -path '*/bin/rustc' -type f -print -quit 2>/dev/null | grep -q .; then
  echo "E_RISC0_RUST_TOOLCHAIN_MISSING: rzup did not install a Risc0 Rust toolchain" >&2
  exit 2
fi

if ! find "${RISC0_HOME:-${HOME}/.risc0}/toolchains" -path '*/bin/riscv32-unknown-elf-gcc' -type f -print -quit 2>/dev/null | grep -q .; then
  echo "E_RISC0_CPP_TOOLCHAIN_MISSING: rzup did not install the Risc0 C++ toolchain" >&2
  exit 2
fi

log "Risc0 toolchain ready"
