#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

usage() {
  cat <<'EOF'
Usage: scripts/ci-local.sh [mode]

Modes:
  all             Run every push/PR job that should pass locally.
  scripts         Bash syntax + helper-script lint.
  rust            Mirrors the GitHub Actions rust job.
  logos           Mirrors the GitHub Actions logos/package job.
  localnet-e2e    Mirrors the push/PR localnet job; may skip like CI.
  quick           Tracked-file check, shell syntax, cargo metadata, rustfmt.
  tracked         Check files CI needs are tracked by git.

The Risc0 method build needs rzup. Install it with:
  curl -L https://risczero.com/install | bash
  ~/.risc0/bin/rzup install rust
EOF
}

mode="${1:-quick}"
if [[ "${mode}" == "-h" || "${mode}" == "--help" ]]; then
  usage
  exit 0
fi

log() {
  printf '[distributionx-ci-local] %s\n' "$*"
}

# `cargo fmt --all` also descends into vendored path-dependency crates
# (vendor/spel-framework/*) — upstream forks we keep verbatim and which rustfmt
# cannot even format cleanly. Format only first-party workspace members.
first_party_fmt_check() {
  local pkgs
  pkgs="$(cargo metadata --no-deps --format-version 1 \
    | python3 -c 'import json,sys; print(" ".join("-p "+p["name"] for p in json.load(sys.stdin)["packages"] if "/vendor/" not in p["manifest_path"]))')"
  log "cargo fmt ${pkgs} -- --check"
  # shellcheck disable=SC2086
  cargo fmt ${pkgs} -- --check
}

nix_build() {
  nix --extra-experimental-features 'nix-command flakes' build -L "$@"
}

run_tracked_check() {
  if [[ "${DISTRIBUTIONX_CI_LOCAL_SKIP_TRACKED:-0}" == "1" ]]; then
    log "skipping tracked-file check because DISTRIBUTIONX_CI_LOCAL_SKIP_TRACKED=1"
    return
  fi
  if ! command -v git >/dev/null 2>&1; then
    log "git not found; skipping tracked-file check"
    return
  fi
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log "not inside a git worktree; skipping tracked-file check"
    return
  fi

  local missing=0
  local required=(
    ".github/workflows/distributionx-ci.yml"
    ".gitignore"
    "Cargo.lock"
    "Cargo.toml"
    "README.md"
    "DistributionX.system-architecture.excalidraw"
    "docs/TESTNET_EVIDENCE.md"
    # Sentinel for the committed testnet verification artifacts: if docs/testnet-evidence/
    # gets re-gitignored, the submission's evidence links break — fail loudly here.
    "docs/testnet-evidence/b1/gettransaction-b1.jsonl"
    "scripts/ci-local.sh"
    "scripts/risc0-setup.sh"
    # Sentinels for the vendored spel-framework fork: if the whole tree is ever
    # re-gitignored (the original CI break), these stop being tracked and fail.
    "vendor/spel-framework/Cargo.toml"
    "vendor/spel-framework/spel-framework/Cargo.toml"
    "vendor/spel-framework/spel-framework-macros/src/lib.rs"
  )
  # nssa_core + fixtures: every file is a build input and must be tracked.
  while IFS= read -r file; do
    required+=("${file}")
  done < <(find vendor/nssa_core fixtures/reviewer-fast-path -type f | sort)

  for file in "${required[@]}"; do
    if [[ ! -f "${file}" ]]; then
      printf '[distributionx-ci-local] missing required file: %s\n' "${file}" >&2
      missing=1
      continue
    fi
    if ! git ls-files --error-unmatch "${file}" >/dev/null 2>&1; then
      printf '[distributionx-ci-local] file exists locally but is not tracked: %s\n' "${file}" >&2
      missing=1
    fi
  done

  # Any source under vendor/spel-framework that exists, is NOT gitignored (the
  # fork's own .gitignore excludes target/ and Cargo.lock), but is untracked —
  # i.e. vendoring was partially skipped. Respects .gitignore so derived locks
  # don't trip the check.
  local untracked_vendored
  untracked_vendored="$(git ls-files --others --exclude-standard vendor/spel-framework 2>/dev/null)"
  if [[ -n "${untracked_vendored}" ]]; then
    while IFS= read -r file; do
      printf '[distributionx-ci-local] untracked (not gitignored) vendored file: %s\n' "${file}" >&2
    done <<<"${untracked_vendored}"
    missing=1
  fi

  if [[ "${missing}" -ne 0 ]]; then
    printf '[distributionx-ci-local] tracked-file check failed; CI will not see the files above.\n' >&2
    exit 2
  fi
}

run_scripts_check() {
  log "bash -n scripts/*.sh"
  shopt -s nullglob
  local fail=0
  local script
  for script in scripts/*.sh; do
    if ! bash -n "${script}"; then
      printf '[distributionx-ci-local] syntax error in %s\n' "${script}" >&2
      fail=1
    fi
  done
  [[ "${fail}" -eq 0 ]]
}

ensure_risc0_toolchain() {
  bash scripts/risc0-setup.sh
}

run_rust_job() {
  log "job rust"
  if command -v rustup >/dev/null 2>&1; then
    log "syncing stable Rust toolchain to match dtolnay/rust-toolchain@stable"
    rustup update stable
  fi
  first_party_fmt_check

  log "cargo test"
  RISC0_SKIP_BUILD=1 cargo test \
    -p distributionx-bindings \
    -p distributionx-wallet-ref \
    -p distributionx-tree \
    -p distributionx-circuit \
    -p distributionx-program \
    -p distributionx-client \
    -p distributionx-cli \
    -p distributionx-relayer-ref

  log "checking generated LEZ client bindings"
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' RETURN
  cargo run -q --manifest-path crates/lez-client-gen/Cargo.toml -- --idl-dir idl --out-dir "${tmpdir}"
  diff -ru "${tmpdir}" src/generated

  log "cargo check guest-facing no-default-features"
  cargo check -p distributionx-wallet-ref -p distributionx-tree -p distributionx-circuit --no-default-features

  log "cargo build -p example_program_deployment_methods"
  ensure_risc0_toolchain
  cargo build -p example_program_deployment_methods

  log "cargo clippy"
  RISC0_SKIP_BUILD=1 cargo clippy --workspace --all-targets -- -D warnings
}

run_logos_job() {
  log "job logos"
  log "nix build distributionx_client_module"
  (cd distributionx_client_module && nix_build)

  log "nix build distributionx_client_module#unit-tests"
  (cd distributionx_client_module && nix_build .#unit-tests)

  log "nix build basecamp-app"
  (cd basecamp-app && nix_build)

  log "nix build basecamp-app#integration-test"
  (cd basecamp-app && nix_build .#integration-test)

  log "bash scripts/package.sh"
  ensure_risc0_toolchain
  bash scripts/package.sh
}

run_localnet_e2e_job() {
  log "job localnet-e2e"
  export DISTRIBUTIONX_LOCALNET_E2E_ALLOW_SKIP="${DISTRIBUTIONX_LOCALNET_E2E_ALLOW_SKIP:-1}"
  export DISTRIBUTIONX_LOCALNET_RPC_URL="${DISTRIBUTIONX_LOCALNET_RPC_URL:-http://127.0.0.1:3040}"
  ensure_risc0_toolchain
  bash scripts/e2e.sh ci-localnet
}

run_quick() {
  run_tracked_check
  run_scripts_check
  log "cargo metadata"
  cargo metadata --no-deps --format-version 1 >/dev/null
  first_party_fmt_check
}

case "${mode}" in
  quick)
    run_quick
    ;;
  rust)
    run_tracked_check
    run_scripts_check
    run_rust_job
    ;;
  logos)
    run_tracked_check
    run_scripts_check
    run_logos_job
    ;;
  scripts)
    run_scripts_check
    ;;
  tracked)
    run_tracked_check
    ;;
  localnet-e2e)
    run_tracked_check
    run_scripts_check
    run_localnet_e2e_job
    ;;
  all)
    run_tracked_check
    run_scripts_check
    run_rust_job
    run_logos_job
    run_localnet_e2e_job
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

log "${mode} checks passed"
