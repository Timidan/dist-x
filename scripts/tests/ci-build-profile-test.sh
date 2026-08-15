#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  printf 'ci-build-profile-test: %s\n' "$*" >&2
  exit 1
}

grep -Fq 'target/release/build/example_program_deployment_methods-' \
  "${ROOT}/scripts/deploy.sh" \
  || fail "deploy does not read release-profile method metadata"
if grep -Fq 'target/debug/build/example_program_deployment_methods-' \
  "${ROOT}/scripts/deploy.sh"; then
  fail "deploy still reads a debug-profile method build"
fi
if grep -Eq 'cargo \+1\.94\.0 run .*distributionx-cli.*method-id' \
  "${ROOT}/scripts/deploy.sh"; then
  fail "deploy still rebuilds the CLI in debug mode for method-id"
fi

for adapter in local-submit.sh local-token-mint.sh; do
  path="${ROOT}/scripts/${adapter}"
  grep -Fq 'DISTRIBUTIONX_ADAPTER_TARGET_DIR' "${path}" \
    || fail "${adapter} has no shared adapter target override"
  grep -Fq 'scripts/adapter-lock/Cargo.lock' "${path}" \
    || fail "${adapter} does not start from the reviewed adapter lock"
  grep -Eq 'cargo \+1\.94\.0 fetch .*--locked.*--manifest-path' "${path}" \
    || fail "${adapter} does not fetch from the reviewed lock"
  main_line="$(grep -nF 'cat > "${ADAPTER_DIR}/src/main.rs"' "${path}" | head -n 1 | cut -d: -f1)"
  fetch_line="$(grep -nE 'cargo \+1\.94\.0 fetch .*--locked.*--manifest-path' "${path}" | head -n 1 | cut -d: -f1)"
  [[ -n "${main_line}" && -n "${fetch_line}" && "${main_line}" -lt "${fetch_line}" ]] \
    || fail "${adapter} fetches before generating its Cargo target"
  grep -Eq 'cargo \+1\.94\.0 (check|run).*--locked.*--release' "${path}" \
    || fail "${adapter} does not use pinned, locked release Cargo"
  if grep -Eq '^[[:space:]]*cargo (check|run)' "${path}"; then
    fail "${adapter} still invokes floating Cargo"
  fi
done
[[ -s "${ROOT}/scripts/adapter-lock/Cargo.lock" ]] \
  || fail "reviewed adapter lock is missing"

local_submit="${ROOT}/scripts/local-submit.sh"
adapter_manifest="${ROOT}/scripts/adapter-lock/Cargo.toml"
grep -Fq 'risc0-zkvm = { version = "=3.0.5"' "${local_submit}" \
  || fail "local submit adapter cannot execute the pinned claim CU measurement"
grep -Fq 'risc0-zkvm = { version = "=3.0.5"' "${adapter_manifest}" \
  || fail "reviewed adapter manifest does not pin claim CU measurement"
grep -Fq 'ADAPTER_STDERR="${ADAPTER_DIR}/stderr-${op}.log"' "${local_submit}" \
  || fail "local submit overwrites per-operation cycle evidence"
grep -Fq 'ADAPTER_STDOUT="${ADAPTER_DIR}/stdout-${op}.log"' "${local_submit}" \
  || fail "local submit overwrites per-operation stdout evidence"
grep -Fq 'DISTRIBUTIONX_LEZ_CU kind=private-program' "${local_submit}" \
  || fail "local submit does not emit claim private-program CU"
grep -Fq 'Validated transaction with hash ${tx_id},' "${local_submit}" \
  || fail "public-operation CU capture is not scoped to its transaction"

workflow="${ROOT}/.github/workflows/distributionx-ci.yml"
mapfile -t workflow_block_timeouts < <(
  sed -nE \
    's/^[[:space:]]*DISTRIBUTIONX_SEQUENCER_BLOCK_CREATE_TIMEOUT: "([^"]+)"[[:space:]]*$/\1/p' \
    "${workflow}"
)
mapfile -t standalone_block_timeouts < <(
  sed -nE \
    's/^[[:space:]]*BLOCK_CREATE_TIMEOUT="\$\{DISTRIBUTIONX_SEQUENCER_BLOCK_CREATE_TIMEOUT:-([^}]+)\}"[[:space:]]*$/\1/p' \
    "${ROOT}/scripts/standalone-sequencer.sh"
)
[[ "${#workflow_block_timeouts[@]}" -eq 1 ]] \
  || fail "canonical workflow must set exactly one block creation timeout"
[[ "${#standalone_block_timeouts[@]}" -eq 1 ]] \
  || fail "standalone sequencer must define exactly one block creation timeout default"
[[ "${workflow_block_timeouts[0]}" == "5s" ]] \
  || fail "canonical workflow block creation timeout must be exactly 5s"
[[ "${standalone_block_timeouts[0]}" == "${workflow_block_timeouts[0]}" ]] \
  || fail "standalone block creation default must exactly match the canonical workflow"
grep -Fq 'cargo +1.94.0 build --locked -p distributionx-cli' "${ROOT}/scripts/package.sh" \
  || fail "LGX packaging does not use pinned, locked Rust"
grep -Fq 'RISC0_CARGO_BIN_DIR="${CARGO_HOME:-${HOME}/.cargo}/bin"' \
  "${ROOT}/scripts/risc0-setup.sh" \
  || fail "Risc0 setup does not resolve rzup-installed binaries from CARGO_HOME"
grep -Fq 'printf '\''%s\n'\'' "${RISC0_CARGO_BIN_DIR}" >> "${GITHUB_PATH}"' \
  "${ROOT}/scripts/risc0-setup.sh" \
  || fail "Risc0 setup does not persist CARGO_HOME/bin for later Actions steps"
grep -Fq 'r0vm --version' "${ROOT}/scripts/risc0-setup.sh" \
  || fail "Risc0 setup does not verify that r0vm is callable before returning"
grep -Fq '"${RZUP_BIN}" default r0vm "${RISC0_R0VM_VERSION}"' \
  "${ROOT}/scripts/risc0-setup.sh" \
  || fail "Risc0 setup does not reactivate an already-installed r0vm"
grep -Fq 'test "${GITHUB_REF_NAME}" = "v${core_version}"' "${workflow}" \
  || fail "release tag is not required to match the package versions"
grep -Fq 'RISC0_INFO: "1"' "${workflow}" \
  || fail "canonical lifecycle does not capture Risc0 cycle metrics"
grep -Fq 'id: lifecycle-log-scan' "${workflow}" \
  || fail "lifecycle evidence scan has no stable step id"
grep -Fq "if: always() && steps.lifecycle-log-scan.outcome == 'success'" "${workflow}" \
  || fail "lifecycle evidence can upload after a failed private-material scan"
grep -Fq 'scan_paths+=(target/distributionx-localnet/receipts)' "${workflow}" \
  || fail "lifecycle receipt artifacts are not scanned before upload"
grep -Fq 'if grep -R -E -i -q \' "${workflow}" \
  || fail "private-material scan can echo a matching secret into the Actions log"

grep -Fq 'DISTRIBUTIONX_USE_CUSTOM_TOKEN_SETTLEMENT:-0' "${ROOT}/scripts/e2e.sh" \
  || fail "canonical local E2E defaults into deferred custom-token settlement"
grep -Fq 'DISTRIBUTIONX_USE_CUSTOM_TOKEN_SETTLEMENT:-0' "${ROOT}/scripts/ci-local.sh" \
  || fail "local CI does not mirror the workflow no-custom-token default"
grep -Fq 'DISTRIBUTIONX_SOURCE_COMMIT=' "${ROOT}/scripts/e2e.sh" \
  || fail "reviewer E2E does not display the exact source commit"
grep -Fq 'DISTRIBUTIONX_SOURCE_DIRTY=' "${ROOT}/scripts/e2e.sh" \
  || fail "reviewer E2E does not disclose a dirty source tree"
grep -Fq 'if [[ "${mode}" == "testnet" ]]' "${ROOT}/scripts/e2e.sh" \
  || fail "public compatibility smoke has no testnet-specific close default"
grep -Fq 'DISTRIBUTIONX_CLOSE_SKIPPED mode=${mode}' "${ROOT}/scripts/e2e.sh" \
  || fail "public compatibility smoke cannot prove that close was skipped"

for guarded in deploy.sh local-submit.sh local-token-mint.sh standalone-sequencer.sh wallet-bootstrap.sh; do
  grep -Fq 'scripts/lez-source-guard.sh' "${ROOT}/scripts/${guarded}" \
    || fail "${guarded} does not validate the exact clean LEZ checkout"
done

echo "ci-build-profile-test: PASS"
