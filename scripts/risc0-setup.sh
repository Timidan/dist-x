#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[distributionx-risc0] %s\n' "$*"
}

RISC0_RUST_VERSION="${RISC0_RUST_VERSION:-1.94.1}"
RISC0_CPP_VERSION="${RISC0_CPP_VERSION:-2024.1.5}"
RISC0_CARGO_RISCZERO_VERSION="${RISC0_CARGO_RISCZERO_VERSION:-3.0.5}"
RISC0_R0VM_VERSION="${RISC0_R0VM_VERSION:-3.0.5}"

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

RISC0_CARGO_BIN_DIR="${CARGO_HOME:-${HOME}/.cargo}/bin"
export PATH="$(dirname "${RZUP_BIN}"):${RISC0_CARGO_BIN_DIR}:${PATH}"
if [[ -n "${GITHUB_PATH:-}" ]]; then
  dirname "${RZUP_BIN}" >> "${GITHUB_PATH}"
  printf '%s\n' "${RISC0_CARGO_BIN_DIR}" >> "${GITHUB_PATH}"
fi

log "Using ${RZUP_BIN}"
RZUP_SHOW="$("${RZUP_BIN}" show 2>/dev/null || true)"

component_installed() {
  local component="$1"
  local version="$2"
  printf '%s\n' "${RZUP_SHOW}" | awk -v component="${component}" -v version="${version}" '
    $0 == component { in_component = 1; next }
    in_component && $1 == "*" && $2 == version { found = 1; exit }
    in_component && NF && $1 != "*" { in_component = 0 }
    END { exit(found ? 0 : 1) }
  '
}

install_component() {
  local component="$1"
  local version="$2"
  if component_installed "${component}" "${version}"; then
    log "${component} ${version} already installed"
    return
  fi
  "${RZUP_BIN}" install "${component}" "${version}"
  RZUP_SHOW="$("${RZUP_BIN}" show 2>/dev/null || true)"
}

install_component rust "${RISC0_RUST_VERSION}"
install_component cpp "${RISC0_CPP_VERSION}"
install_component cargo-risczero "${RISC0_CARGO_RISCZERO_VERSION}"
install_component r0vm "${RISC0_R0VM_VERSION}"
"${RZUP_BIN}" default r0vm "${RISC0_R0VM_VERSION}"
printf '%s\n' "${RZUP_SHOW}"

if ! command -v r0vm >/dev/null 2>&1; then
  echo "E_RISC0_R0VM_MISSING: rzup did not expose r0vm under ${RISC0_CARGO_BIN_DIR}" >&2
  exit 2
fi
if ! r0vm --version | grep -Fq "${RISC0_R0VM_VERSION}"; then
  echo "E_RISC0_R0VM_VERSION: expected ${RISC0_R0VM_VERSION}" >&2
  exit 2
fi

if ! find "${RISC0_HOME:-${HOME}/.risc0}/toolchains" -path '*/bin/rustc' -type f -print -quit 2>/dev/null | grep -q .; then
  echo "E_RISC0_RUST_TOOLCHAIN_MISSING: rzup did not install a Risc0 Rust toolchain" >&2
  exit 2
fi

if ! find "${RISC0_HOME:-${HOME}/.risc0}/toolchains" -path '*/bin/riscv32-unknown-elf-gcc' -type f -print -quit 2>/dev/null | grep -q .; then
  echo "E_RISC0_CPP_TOOLCHAIN_MISSING: rzup did not install the Risc0 C++ toolchain" >&2
  exit 2
fi

log "Risc0 toolchain ready"
