#!/usr/bin/env bash
# LP-0003: a deliberately fail-closed, two-approval public evidence runner.
set -euo pipefail
umask 077

die() { printf 'E_DISTRIBUTIONX_EVIDENCE: %s\n' "$*" >&2; exit 1; }
CANONICAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGRESSION_TEST_MODE="${DISTRIBUTIONX_EVIDENCE_REGRESSION_TEST:-0}"
case "${REGRESSION_TEST_MODE}" in
  0|1) ;;
  *) die 'DISTRIBUTIONX_EVIDENCE_REGRESSION_TEST must be 0 or 1' ;;
esac

if [[ "${REGRESSION_TEST_MODE}" == 0 ]]; then
  [[ -z "${DISTRIBUTIONX_EVIDENCE_REPO_ROOT:-}" && -z "${DISTRIBUTIONX_CLI:-}" && \
     -z "${DISTRIBUTIONX_EVIDENCE_FINGERPRINT_SCRIPT:-}" && -z "${DISTRIBUTIONX_EVIDENCE_DEPLOY_SCRIPT:-}" && \
     -z "${DISTRIBUTIONX_LEZ_REPO:-}" ]] \
    || die 'production mode forbids noncanonical evidence path overrides'
  [[ -z "${LEZ_DEPLOY_COMMAND:-}" && -z "${LEZ_WALLET_BIN:-}" && -z "${LEE_WALLET_HOME_DIR:-}" ]] \
    || die 'production evidence forbids inherited deployment overrides'
  ROOT="${CANONICAL_ROOT}"
  CLI="${ROOT}/target/release/distributionx-cli"
  FINGERPRINT_SCRIPT="${ROOT}/scripts/lez-fingerprint.sh"
  DEPLOY_SCRIPT="${ROOT}/scripts/deploy.sh"
  LEZ_REPO="${ROOT}/.scaffold/cache/repos/lez/v0.2.4"
else
  ROOT="${DISTRIBUTIONX_EVIDENCE_REPO_ROOT:-${CANONICAL_ROOT}}"
  CLI="${DISTRIBUTIONX_CLI:-${ROOT}/target/release/distributionx-cli}"
  FINGERPRINT_SCRIPT="${DISTRIBUTIONX_EVIDENCE_FINGERPRINT_SCRIPT:-${ROOT}/scripts/lez-fingerprint.sh}"
  DEPLOY_SCRIPT="${DISTRIBUTIONX_EVIDENCE_DEPLOY_SCRIPT:-${ROOT}/scripts/deploy.sh}"
  LEZ_REPO="${DISTRIBUTIONX_LEZ_REPO:-${ROOT}/.scaffold/cache/repos/lez/v0.2.4}"
fi
STATE_BASE="${DISTRIBUTIONX_EVIDENCE_STATE_BASE:-${ROOT}/target/testnet-evidence}"
EXPECTED_LEZ_COMMIT=47eba256479f6f785acbd138834340703cd03401

usage() { cat <<'EOF'
Usage: scripts/testnet-evidence.sh prepare|smoke QUOTE_SHA256|finish QUOTE_SHA256|verify

prepare makes private state only. smoke and finish are separately approved
public-write phases. verify is read-only and publishes only scrubbed public RPC
responses and an LP-0003 manifest.
EOF
}
is_hex64() { [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }
is_regression_mode() { [[ "${REGRESSION_TEST_MODE}" == 1 ]]; }
is_invalid_rpc_host() { [[ "$1" =~ ^https://[^/:]+\.invalid([/:]|$) ]]; }
cli_sha256() { sha256sum "${CLI}" | awk '{print $1}'; }
build_cli_for_prepare() {
  if ! is_regression_mode; then
    cargo +1.94.0 build --locked --release -p distributionx-cli
  fi
  [[ -x "${CLI}" ]] || die "CLI is not executable: ${CLI}"
}
assert_cli_sha256() {
  local expected="$1" actual
  [[ "${expected}" =~ ^[0-9a-f]{64}$ ]] || die 'quote has invalid distributionx-cli SHA-256'
  actual="$(cli_sha256)"
  [[ "${actual}" == "${expected}" ]] || die 'distributionx-cli SHA-256 changed'
}
run_id() { printf '%s\n' "${DISTRIBUTIONX_EVIDENCE_RUN_ID:?DISTRIBUTIONX_EVIDENCE_RUN_ID required}"; }
run_root() { printf '%s/%s\n' "${STATE_BASE}" "$(run_id)"; }
private_root() { printf '%s/private\n' "$(run_root)"; }
public_root() { printf '%s/public\n' "$(run_root)"; }
quote_path() { printf '%s/quote.json\n' "$(private_root)"; }
quote_digest_path() { printf '%s/quote.sha256\n' "$(private_root)"; }
journal_path() { printf '%s/journal/%s.json\n' "$(private_root)" "$1"; }
receipt_dir() { printf '%s/receipts/%s\n' "$(private_root)" "$1"; }
state_dir() { printf '%s/distributions/%s/state\n' "$(private_root)" "$1"; }
wallet_home() { printf '%s/wallet\n' "$(private_root)"; }
wallet_config() { printf '%s/wallet_config.json\n' "$(wallet_home)"; }

operations() {
  printf '%s\n' deploy a-init a-prefund a-fund b-init b-prefund b-fund
  local part n
  for part in a b; do for n in $(seq -w 1 10); do printf '%s-claim-%s\n' "${part}" "${n}"; done; done
}
phase_operations() {
  case "$1" in
    smoke) printf '%s\n' deploy a-init a-prefund a-fund a-claim-01 ;;
    finish) local n; for n in $(seq -w 2 10); do printf 'a-claim-%s\n' "${n}"; done; printf '%s\n' b-init b-prefund b-fund; for n in $(seq -w 1 10); do printf 'b-claim-%s\n' "${n}"; done ;;
    *) die "unknown phase: $1" ;;
  esac
}

release_tag_ok() { [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9._-]+)?$ ]]; }
require_runtime() {
  [[ "${RISC0_DEV_MODE:-}" == 0 ]] || die 'RISC0_DEV_MODE must equal 0'
  [[ -x "${CLI}" ]] || die "CLI is not executable: ${CLI}"
  [[ "${LEZ_RPC_URL:-}" == https://* ]] || die 'LEZ_RPC_URL must be non-local HTTPS'
  [[ ! "${LEZ_RPC_URL}" =~ (localhost|127\.0\.0\.1|\[::1\]) ]] || die 'localhost RPC is forbidden'
  if is_regression_mode; then
    is_invalid_rpc_host "${LEZ_RPC_URL}" || die 'regression mode requires an HTTPS .invalid RPC host'
  fi
  [[ "$(run_id)" =~ ^[a-z0-9][a-z0-9._-]{5,80}$ ]] || die 'run id must be safe and fresh'
  release_tag_ok "${DISTRIBUTIONX_RELEASE_TAG:-}" || die 'release tag must be a vX.Y.Z tag'
  [[ "${DISTRIBUTIONX_USE_CUSTOM_TOKEN_SETTLEMENT:-0}" == 0 ]] || die 'custom token settlement is forbidden'
  [[ -z "${DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT:-}" ]] || die 'token source account must be empty'
  [[ "${DISTRIBUTIONX_USE_CLAIM_PRIVATE:-0}" == 0 ]] || die 'claim_private is forbidden'
  [[ "${LEZ_DEPLOYER_WALLET:-}" == Public/* ]] || die 'funded deployer wallet is required'
  [[ -n "${DISTRIBUTIONX_TOKEN_ID:-}" && -n "${DISTRIBUTIONX_RECOVERY_ADDRESS:-}" ]] || die 'native token and recovery address are required'
  [[ "${DISTRIBUTIONX_EXPIRY_UNIX:-}" =~ ^[0-9]+$ ]] || die 'expiry is required'
  [[ -n "${DISTRIBUTIONX_RELAYER_URL:-}" ]] || die 'relayer is required'
  git -C "${ROOT}" diff --quiet --ignore-submodules HEAD -- || die 'source tree is dirty'
  [[ -z "$(git -C "${ROOT}" ls-files --others --exclude-standard)" ]] || die 'source tree has untracked files'
  [[ "$(bash "${ROOT}/scripts/lez-source-guard.sh" "${LEZ_REPO}")" == "${EXPECTED_LEZ_COMMIT}" ]] || die 'LEZ source guard failed'
}
fingerprint() { "${FINGERPRINT_SCRIPT}" --rpc "${LEZ_RPC_URL}"; }
fingerprint_identity() {
  jq -cS '{rpc_url,channel_id,program_ids,compatibility:{builtins_match,latest_matching_release,pinned_commit,exact_server_version_confirmed}}'
}
check_fingerprint() {
  local value="$1"
  jq -e --arg commit "${EXPECTED_LEZ_COMMIT}" '.healthy == true and .compatibility.pinned_commit == $commit and .compatibility.builtins_match == true' >/dev/null <<<"${value}" || die 'invalid LEZ fingerprint'
}
normalize_private_permissions() {
  find "$(private_root)" -type d -exec chmod 700 {} +
  find "$(private_root)" -type f -exec chmod 600 {} +
}

write_evidence_wallet_config() {
  local home config
  home="$(wallet_home)"; config="$(wallet_config)"
  mkdir -p "${home}"; chmod 700 "${home}"
  jq -n --arg rpc "${LEZ_RPC_URL}" \
    '{
      sequencers:[{sequencer_addr:$rpc,basic_auth:null}],
      seq_poll_timeout:"12s",
      seq_tx_poll_max_blocks:5,
      seq_poll_max_retries:5,
      seq_block_poll_max_amount:100,
      multi_sequencer_client_config:{distribution_limit:1,calibration_limit:100}
    }' >"${config}"
  chmod 600 "${config}"
}

rpc_get() {
  local tx="$1" response
  is_hex64 "${tx}" || die "invalid transaction hash: ${tx}"
  response="$(curl --fail-with-body --silent --show-error --max-time 20 --header 'content-type: application/json' --data "$(jq -nc --arg hash "${tx}" '{jsonrpc:"2.0",id:1,method:"getTransaction",params:[$hash]}')" "${LEZ_RPC_URL}")" || die "getTransaction failed for ${tx}"
  jq -e '.error == null and (.result | type == "array" and length == 2 and .[0] != null and (.[1] | type == "number") and ((.[0] | type == "object") or ((.[0] | type == "string") and (.[0] | length > 0) and (.[0] | test("^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$")))))' >/dev/null <<<"${response}" || die "getTransaction did not return an included tuple for ${tx}"
  printf '%s\n' "${response}"
}
check_tx() {
  local tx="$1" block="$2" response actual
  response="$(rpc_get "${tx}")"; actual="$(jq -er '.result[1]' <<<"${response}")"
  [[ "${actual}" == "${block}" ]] || die "included block mismatch for ${tx}"
  # Some compatible LEZ responses expose transaction_hash; if they do, bind it.
  if jq -e '.result[0] | objects | .transaction_hash? != null' >/dev/null <<<"${response}"; then
    [[ "$(jq -r '.result[0].transaction_hash' <<<"${response}")" == "${tx}" ]] || die "RPC returned another transaction"
  fi
  printf '%s\n' "${response}"
}

receipt_file_for() {
  case "$1" in
    deploy) printf '%s/deployment.json\n' "$(receipt_dir deploy)" ;;
    ?-init) printf '%s/init_airdrop.json\n' "$(receipt_dir "$1")" ;;
    ?-fund) printf '%s/fund.json\n' "$(receipt_dir "$1")" ;;
    ?-prefund) printf '%s/fund.json\n' "$(receipt_dir "${1%-prefund}-fund")" ;;
    ?-claim-??) printf '%s/claim.json\n' "$(receipt_dir "$1")" ;;
    *) die "unknown receipt operation: $1" ;;
  esac
}
validate_receipt() {
  local op="$1" file tx block part
  file="$(receipt_file_for "${op}")"; [[ -f "${file}" ]] || die "missing receipt: ${op}"
  if [[ "${op}" == ?-prefund ]]; then
    tx="$(jq -er '.vault_prefund_tx_id | select(test("^[0-9a-f]{64}$"))' "${file}")" || die "invalid receipt tx: ${op}"
    block="$(jq -er '.vault_prefund_block_id | numbers' "${file}")" || die "invalid receipt block: ${op}"
  else
    tx="$(jq -er '.tx_id // .deploy_tx_hash | select(test("^[0-9a-f]{64}$"))' "${file}")" || die "invalid receipt tx: ${op}"
    block="$(jq -er '.block_id // .deploy_block_id | numbers' "${file}")" || die "invalid receipt block: ${op}"
  fi
  case "${op}" in
    deploy)
      jq -e --arg tx "${tx}" --argjson block "${block}" --arg rpc "${LEZ_RPC_URL}" '.status == "DEPLOY_TESTNET_OK" and .rpc_url == $rpc and .deploy_tx_hash == $tx and .deploy_tx_hash == .deterministic_program_deployment_tx_hash and .deploy_block_id == $block and (.program_id | type == "string" and test("^[0-9a-f]{64}$")) and .program_id == .program_image_id_hex and .deploy_signer_account == null and .lez_commit == "47eba256479f6f785acbd138834340703cd03401"' "${file}" >/dev/null || die 'invalid deploy receipt'
      ;;
    ?-init|?-claim-??)
      jq -e --arg tx "${tx}" --argjson block "${block}" '.status == "OK" and .tx_id == $tx and .block_id == $block and .token_tx_id == null' "${file}" >/dev/null || die "invalid receipt: ${op}"
      ;;
    ?-fund)
      jq -e --arg tx "${tx}" --argjson block "${block}" '.status == "OK" and .tx_id == $tx and .block_id == $block and .token_tx_id == null and (.vault_prefund_tx_id | test("^[0-9a-f]{64}$")) and (.vault_prefund_block_id | numbers)' "${file}" >/dev/null || die "invalid fund receipt: ${op}"
      ;;
    ?-prefund)
      part="${op%-prefund}"
      jq -e --arg tx "${tx}" --argjson block "${block}" '.status == "OK" and .token_tx_id == null and .vault_prefund_tx_id == $tx and .vault_prefund_block_id == $block' "${file}" >/dev/null || die "invalid prefund receipt: ${op}"
      ;;
  esac
}
journal_tx() {
  local op="$1" tx="$2" block="$3" file="$(journal_path "$1")" extra='{}'
  [[ ! -e "${file}" ]] || die "journal overwrite risk: ${op}"
  check_tx "${tx}" "${block}" >/dev/null
  if [[ "${op}" == deploy ]]; then
    extra="$(jq -n --arg program_id "$(jq -r .program_id "$(receipt_file_for deploy)")" '{program_id:$program_id}')"
  fi
  jq -n --arg operation "${op}" --arg tx_hash "${tx}" --argjson block_id "${block}" --argjson extra "${extra}" '{operation:$operation,tx_hash:$tx_hash,block_id:$block_id} + $extra' >"${file}"
  chmod 600 "${file}"
}
assert_operation() {
  local op="$1" file tx block
  file="$(journal_path "${op}")"; [[ -f "${file}" ]] || die "missing journal: ${op}"
  validate_receipt "${op}"
  tx="$(jq -er --arg op "${op}" 'select(.operation == $op) | .tx_hash | select(test("^[0-9a-f]{64}$"))' "${file}")" || die "bad journal: ${op}"
  block="$(jq -er '.block_id | numbers' "${file}")" || die "bad journal block: ${op}"
  local rtx rblock
  if [[ "${op}" == ?-prefund ]]; then
    rtx="$(jq -er .vault_prefund_tx_id "$(receipt_file_for "${op}")")"; rblock="$(jq -er .vault_prefund_block_id "$(receipt_file_for "${op}")")"
  else
    rtx="$(jq -er '.tx_id // .deploy_tx_hash' "$(receipt_file_for "${op}")")"; rblock="$(jq -er '.block_id // .deploy_block_id' "$(receipt_file_for "${op}")")"
  fi
  [[ "${tx}" == "${rtx}" && "${block}" == "${rblock}" ]] || die "journal/receipt mismatch: ${op}"
  if [[ "${op}" == deploy ]]; then
    [[ "$(jq -er '.program_id | select(type == "string" and length > 0)' "${file}")" == "$(jq -er .program_id "$(receipt_file_for deploy)")" ]] \
      || die 'deploy journal/receipt program mismatch'
  fi
  check_tx "${tx}" "${block}" >/dev/null
}
ensure_state_deployment() {
  local part="$1" state receipt
  assert_operation deploy
  state="$(state_dir "${part}")"; receipt="$(receipt_file_for deploy)"
  [[ -d "${state}" ]] || die "missing persistent distribution state: ${part}"
  if [[ -e "${state}/deployment.json" ]]; then
    cmp -s "${receipt}" "${state}/deployment.json" || die "state deployment receipt mismatch: ${part}"
  else
    # A bootstrap is allowed only before this distribution's first init. Once
    # init state exists, losing this file is ambiguous and must not be repaired.
    [[ ! -e "$(journal_path "${part}-init")" && ! -e "${state}/state.json" && ! -e "${state}/bundle.json" ]] \
      || die "missing persistent deployment state after init: ${part}"
    cp "${receipt}" "${state}/deployment.json"; chmod 600 "${state}/deployment.json"
  fi
}
assert_distribution_id() {
  local part="$1" expected="$2" state
  state="$(state_dir "${part}")"
  ensure_state_deployment "${part}"
  [[ -f "${state}/state.json" && -f "${state}/bundle.json" ]] || die "missing persistent distribution state data: ${part}"
  [[ "$(jq -er '.airdrop_id | select(test("^[0-9a-f]{64}$"))' "${state}/state.json")" == "${expected}" ]] \
    || die "distribution id/state mismatch: ${part}"
}
require_fresh_operation() {
  local op="$1" dir
  [[ ! -e "$(journal_path "${op}")" ]] || die "journal exists for unfinished operation: ${op}"
  case "${op}" in ?-prefund) return ;; esac
  dir="$(receipt_dir "${op}")"; [[ ! -e "${dir}" ]] || die "receipt exists without journal: ${op}"
}
write_env() {
  unset DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT
  export DISTRIBUTIONX_ENV_FILE="$(private_root)/no-implicit-env.local"
  export LEE_WALLET_HOME_DIR="$(wallet_home)"
  export DISTRIBUTIONX_USE_CUSTOM_TOKEN_SETTLEMENT=0 DISTRIBUTIONX_USE_CLAIM_PRIVATE=0
  export DISTRIBUTIONX_INIT_SUBMIT_COMMAND="bash ${ROOT}/scripts/local-submit.sh init"
  export DISTRIBUTIONX_FUND_SUBMIT_COMMAND="bash ${ROOT}/scripts/local-submit.sh fund"
  export DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND="bash ${ROOT}/scripts/local-submit.sh claim"
}
require_hooks() {
  [[ "${DISTRIBUTIONX_INIT_SUBMIT_COMMAND:-}" == "bash ${ROOT}/scripts/local-submit.sh init" && "${DISTRIBUTIONX_FUND_SUBMIT_COMMAND:-}" == "bash ${ROOT}/scripts/local-submit.sh fund" && "${DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND:-}" == "bash ${ROOT}/scripts/local-submit.sh claim" ]] || die 'unexpected submit hook'
  [[ "${LEE_WALLET_HOME_DIR:-}" == "$(wallet_home)" ]] || die 'unexpected evidence wallet home'
}

prepare() {
  build_cli_for_prepare
  require_runtime
  local private fingerprint source_commit lez_commit cli_hash n slot wallet destination account commitment csv accounts commitments
  private="$(private_root)"; [[ ! -e "$(run_root)" ]] || die 'run id already exists; choose a fresh run id'
  mkdir -p "${private}"/{claimants,journal,receipts,phases} "${private}/distributions/a/state" "${private}/distributions/b/state"
  write_evidence_wallet_config
  normalize_private_permissions
  fingerprint="$(fingerprint)"; check_fingerprint "${fingerprint}"
  printf '%s\n' "${fingerprint}" >"${private}/fingerprint.json"
  source_commit="$(git -C "${ROOT}" rev-parse HEAD)"; lez_commit="$(bash "${ROOT}/scripts/lez-source-guard.sh" "${LEZ_REPO}")"; cli_hash="$(cli_sha256)"
  for n in $(seq -w 1 20); do
    slot="${private}/claimants/${n}"; mkdir -p "${slot}"; chmod 700 "${slot}"
    wallet="$("${CLI}" create-wallet --out-dir "${slot}")"; account="$(jq -er '.account | sub("^Public/"; "") | select(test("^[0-9a-f]{64}$"))' <<<"${wallet}")" || die "invalid wallet ${n}"
    destination="$("${CLI}" create-destination --out-dir "${slot}")"; commitment="$(jq -er '.claim_destination_commitment | select(test("^[0-9a-f]{64}$"))' <<<"${destination}")" || die "invalid destination ${n}"
    printf '%s\n' "${account}" >"${slot}/account.hex"; printf '%s\n' "${commitment}" >"${slot}/commitment.hex"
  done
  accounts="$(find "${private}/claimants" -name account.hex -type f -exec cat {} + | sort -u | wc -l)"; commitments="$(find "${private}/claimants" -name commitment.hex -type f -exec cat {} + | sort -u | wc -l)"
  [[ "${accounts}" == 20 && "${commitments}" == 20 ]] || die 'claimants or destinations are not unique'
  for part in a b; do printf 'address,raw_amount\n' >"${private}/distributions/${part}/eligible.csv"; done
  for n in $(seq -w 1 20); do
    if ((10#${n} <= 10)); then csv="${private}/distributions/a/eligible.csv"; else csv="${private}/distributions/b/eligible.csv"; fi
    printf '%s,1\n' "$(<"${private}/claimants/${n}/account.hex")" >>"${csv}"
  done
  jq -n --arg source "${source_commit}" --arg tag "${DISTRIBUTIONX_RELEASE_TAG}" --arg lez_commit "${lez_commit}" --arg cli_sha256 "${cli_hash}" --argjson fingerprint "${fingerprint}" --argjson fingerprint_identity "$(fingerprint_identity <<<"${fingerprint}")" --arg rpc "${LEZ_RPC_URL}" --arg deployer "${LEZ_DEPLOYER_WALLET}" --arg token "${DISTRIBUTIONX_TOKEN_ID}" --arg expiry "${DISTRIBUTIONX_EXPIRY_UNIX}" --arg recovery "${DISTRIBUTIONX_RECOVERY_ADDRESS}" --arg relayer "${DISTRIBUTIONX_RELAYER_URL}" '{schema_version:"distributionx-lp0003-quote-v1",execution_source_commit:$source,release_tag:$tag,planned_release_tag:$tag,lez_commit:$lez_commit,distributionx_cli_sha256:$cli_sha256,rpc_url:$rpc,rpc_fingerprint:$fingerprint,rpc_fingerprint_identity:$fingerprint_identity,deployer_wallet:$deployer,token_id:$token,expiry_unix:$expiry,recovery_address:$recovery,relayer_url:$relayer,claim_amount_raw:1,distribution_funding_raw:10,write_counts:{smoke:5,finish:22,total:27},deployer:{already_funded_assumption:true,initialization_or_funding_in_scope:false},custom_token_settlement:false,close:false}' >"$(quote_path)"
  sha256sum "$(quote_path)" | awk '{print $1}' >"$(quote_digest_path)"; normalize_private_permissions
  printf 'prepared quote SHA-256: %s\n' "$(<"$(quote_digest_path)")"
}
require_quote() {
  [[ $# -ge 1 && $# -le 2 ]] || die 'this phase requires the exact prepare quote SHA-256'
  require_runtime
  local stored actual supplied current expected_identity cli_hash mode="${2:-write}" source tag_source
  [[ "${mode}" == write || "${mode}" == verify ]] || die 'invalid quote verification mode'
  stored="$(<"$(quote_digest_path)")" || die 'prepare quote missing'; actual="$(sha256sum "$(quote_path)" | awk '{print $1}')"; supplied="${1,,}"
  is_hex64 "${stored}" && [[ "${stored}" == "${actual}" && "${actual}" == "${supplied}" ]] || die 'quote digest is not immutable or approved'
  current="$(fingerprint)"; check_fingerprint "${current}"; expected_identity="$(jq -cS '.rpc_fingerprint_identity' "$(quote_path)")"
  [[ "$(fingerprint_identity <<<"${current}")" == "${expected_identity}" ]] || die 'RPC/channel fingerprint changed'
  cli_hash="$(jq -er '.distributionx_cli_sha256 | select(test("^[0-9a-f]{64}$"))' "$(quote_path)")" || die 'quote has invalid distributionx-cli SHA-256'
  assert_cli_sha256 "${cli_hash}"
  source="$(git -C "${ROOT}" rev-parse HEAD)"
  if [[ "${mode}" == verify && "${source}" != "$(jq -r .execution_source_commit "$(quote_path)")" ]]; then
    tag_source="$(git -C "${ROOT}" rev-parse --verify "${DISTRIBUTIONX_RELEASE_TAG}^{commit}")" || die 'quoted release tag is unavailable'
    [[ "${tag_source}" == "$(jq -r .execution_source_commit "$(quote_path)")" ]] || die 'quoted release tag no longer resolves to execution source'
    source="${tag_source}"
  fi
  jq -e --arg source "${source}" --arg tag "${DISTRIBUTIONX_RELEASE_TAG}" --arg lez "${EXPECTED_LEZ_COMMIT}" --arg cli_sha256 "${cli_hash}" --arg rpc "${LEZ_RPC_URL}" --arg deployer "${LEZ_DEPLOYER_WALLET}" --arg token "${DISTRIBUTIONX_TOKEN_ID}" --arg expiry "${DISTRIBUTIONX_EXPIRY_UNIX}" --arg recovery "${DISTRIBUTIONX_RECOVERY_ADDRESS}" --arg relayer "${DISTRIBUTIONX_RELAYER_URL}" '.execution_source_commit == $source and .release_tag == $tag and .planned_release_tag == $tag and .lez_commit == $lez and .distributionx_cli_sha256 == $cli_sha256 and .rpc_url == $rpc and .deployer_wallet == $deployer and .token_id == $token and .expiry_unix == $expiry and .recovery_address == $recovery and .relayer_url == $relayer and .claim_amount_raw == 1 and .distribution_funding_raw == 10 and .write_counts == {smoke:5,finish:22,total:27} and .custom_token_settlement == false and .close == false and .deployer.already_funded_assumption == true and .deployer.initialization_or_funding_in_scope == false' "$(quote_path)" >/dev/null || die 'runtime differs from approved quote'
}

run_deploy() {
  local dir tx block cli_hash config home
  if [[ -f "$(journal_path deploy)" ]]; then assert_operation deploy; ensure_state_deployment a; ensure_state_deployment b; return; fi
  require_fresh_operation deploy; dir="$(receipt_dir deploy)"; mkdir -p "${dir}"; chmod 700 "${dir}"
  cli_hash="$(jq -er .distributionx_cli_sha256 "$(quote_path)")"; assert_cli_sha256 "${cli_hash}"
  config="$(wallet_config)"; home="$(wallet_home)"
  jq -e --arg rpc "${LEZ_RPC_URL}" '.sequencers == [{sequencer_addr:$rpc,basic_auth:null}]' "${config}" >/dev/null \
    || die 'private wallet config is not bound to the quoted RPC'
  DISTRIBUTIONX_STATE_DIR="${dir}" DISTRIBUTIONX_CLI="${CLI}" DISTRIBUTIONX_EVIDENCE_CLI_SHA256="${cli_hash}" \
    DISTRIBUTIONX_EVIDENCE_PROVENANCE=1 DISTRIBUTIONX_EVIDENCE_WALLET_CONFIG="${config}" \
    DISTRIBUTIONX_EVIDENCE_WALLET_HOME="${home}" DISTRIBUTIONX_EVIDENCE_PRIVATE_ROOT="$(private_root)" \
    LEZ_RPC_URL="${LEZ_RPC_URL}" \
    bash "${DEPLOY_SCRIPT}" --testnet >/dev/null || die 'deploy failed'
  assert_cli_sha256 "${cli_hash}"
  validate_receipt deploy; tx="$(jq -r .deploy_tx_hash "$(receipt_file_for deploy)")"; block="$(jq -r .deploy_block_id "$(receipt_file_for deploy)")"; journal_tx deploy "${tx}" "${block}"
  ensure_state_deployment a; ensure_state_deployment b; normalize_private_permissions
}
run_init() {
  local part="$1" op="${1}-init" receipt state out tx block id
  if [[ -f "$(journal_path "${op}")" ]]; then assert_operation "${op}"; ensure_state_deployment "${part}"; return; fi
  require_fresh_operation "${op}"; ensure_state_deployment "${part}"; receipt="$(receipt_dir "${op}")"; state="$(state_dir "${part}")"; mkdir -p "${receipt}"; chmod 700 "${receipt}"
  out="$(DISTRIBUTIONX_STATE_DIR="${state}" DISTRIBUTIONX_RECEIPTS_DIR="${receipt}" DISTRIBUTIONX_AIRDROP_NAME="$(run_id)-${part}" "${CLI}" init --csv "$(private_root)/distributions/${part}/eligible.csv" --distributor "${LEZ_DEPLOYER_WALLET}" --token "${DISTRIBUTIONX_TOKEN_ID}" --token-source-account "" --rpc "${LEZ_RPC_URL}" --expiry "${DISTRIBUTIONX_EXPIRY_UNIX}" --recovery "${DISTRIBUTIONX_RECOVERY_ADDRESS}")"
  tx="$(jq -er '.tx_id | select(test("^[0-9a-f]{64}$"))' <<<"${out}")"; id="$(jq -er '.airdrop_id | select(test("^[0-9a-f]{64}$"))' <<<"${out}")"; block="$(jq -er .block_id "$(receipt_file_for "${op}")")"
  jq -n --arg id "${id}" '{id:$id}' >"$(private_root)/distributions/${part}/id.json"; assert_distribution_id "${part}" "${id}"; validate_receipt "${op}"; journal_tx "${op}" "${tx}" "${block}"; normalize_private_permissions
}
run_fund() {
  local part="$1" op="${1}-fund" receipt state out tx block pretx preblock
  if [[ -f "$(journal_path "${op}")" ]]; then assert_operation "${part}-prefund"; assert_operation "${op}"; ensure_state_deployment "${part}"; return; fi
  require_fresh_operation "${op}"; ensure_state_deployment "${part}"; receipt="$(receipt_dir "${op}")"; state="$(state_dir "${part}")"; mkdir -p "${receipt}"; chmod 700 "${receipt}"
  out="$(DISTRIBUTIONX_STATE_DIR="${state}" DISTRIBUTIONX_RECEIPTS_DIR="${receipt}" DISTRIBUTIONX_AIRDROP_NAME="$(run_id)-${part}" "${CLI}" fund --airdrop "$(run_id)-${part}" --amount 10)"
  tx="$(jq -er '.tx_id | select(test("^[0-9a-f]{64}$"))' <<<"${out}")"; block="$(jq -er .block_id "$(receipt_file_for "${op}")")"; pretx="$(jq -er .vault_prefund_tx_id "$(receipt_file_for "${op}")")"; preblock="$(jq -er .vault_prefund_block_id "$(receipt_file_for "${op}")")"
  validate_receipt "${part}-prefund"; validate_receipt "${op}"; journal_tx "${part}-prefund" "${pretx}" "${preblock}"; journal_tx "${op}" "${tx}" "${block}"; normalize_private_permissions
}
run_claim() {
  local part="$1" number="$2" op="${1}-claim-${2}" receipt state slot out tx block
  if [[ -f "$(journal_path "${op}")" ]]; then assert_operation "${op}"; ensure_state_deployment "${part}"; return; fi
  require_fresh_operation "${op}"; ensure_state_deployment "${part}"; receipt="$(receipt_dir "${op}")"; state="$(state_dir "${part}")"; mkdir -p "${receipt}"; chmod 700 "${receipt}"
  if [[ "${part}" == a ]]; then slot="${number}"; else slot="$(printf '%02d' "$((10#${number}+10))")"; fi
  slot="$(private_root)/claimants/${slot}"
  DISTRIBUTIONX_STATE_DIR="${state}" DISTRIBUTIONX_RECEIPTS_DIR="${receipt}" "${CLI}" prepare-claim-tx --airdrop "$(run_id)-${part}" --bundle "${state}/bundle.json" --wallet "${slot}/wallet.seed" --destination-packet "${slot}/shielded_destination.json" --out "${slot}/claim.tx" >/dev/null
  out="$(DISTRIBUTIONX_STATE_DIR="${state}" DISTRIBUTIONX_RECEIPTS_DIR="${receipt}" DISTRIBUTIONX_AIRDROP_NAME="$(run_id)-${part}" "${CLI}" claim --airdrop "$(run_id)-${part}" --proof "${slot}/unused-proof.json" --relayer "${DISTRIBUTIONX_RELAYER_URL}" --serialized-lez-tx "${slot}/claim.tx")"
  tx="$(jq -er '.tx_id | select(test("^[0-9a-f]{64}$"))' <<<"${out}")"; block="$(jq -er .block_id "$(receipt_file_for "${op}")")"; validate_receipt "${op}"; journal_tx "${op}" "${tx}" "${block}"; normalize_private_permissions
}
write_phase() { jq -n --arg phase "$1" --argjson write_count "$2" '{phase:$phase,write_count:$write_count,complete:true}' >"$(private_root)/phases/$1.json"; chmod 600 "$(private_root)/phases/$1.json"; }
assert_phase() { local op; jq -e --argjson n "$2" '.complete == true and .write_count == $n' "$(private_root)/phases/$1.json" >/dev/null || die "invalid $1 marker"; while IFS= read -r op; do assert_operation "${op}"; done < <(phase_operations "$1"); }
smoke() { require_quote "$@"; write_env; require_hooks; if [[ -f "$(private_root)/phases/smoke.json" ]]; then assert_phase smoke 5; return; fi; run_deploy; run_init a; run_fund a; run_claim a 01; write_phase smoke 5; }
finish() { require_quote "$@"; write_env; require_hooks; assert_phase smoke 5; if [[ -f "$(private_root)/phases/finish.json" ]]; then assert_phase finish 22; return; fi; local n; for n in $(seq -w 2 10); do run_claim a "${n}"; done; run_init b; run_fund b; for n in $(seq -w 1 10); do run_claim b "${n}"; done; write_phase finish 22; }

forbidden_public() { jq -e '((.. | objects | keys[]?), (.. | strings)) | select(test("(seed|eligible|claimant|salt|merkle|private_claim|bundle|claim\\.tx|shielded_destination|secret|recipient_(npk|vpk|identifier)|wallet|target/)"; "i"))' >/dev/null <<<"$1"; }
forbidden_public_rpc() {
  local scrubbed
  scrubbed="$(jq -c 'if (.result | type == "array" and length == 2 and (.[0] | type == "string")) then .result[0] = "<opaque-public-transaction-bytes>" else . end' <<<"$1")"
  forbidden_public "${scrubbed}"
}
verify() {
  [[ $# -eq 0 ]] || die 'verify takes no arguments'; require_runtime
  local private public staging preview op file tx block response ids='[]' txs='[]' pairs='[]' distributions='[]' part n program_id deploy_tx deploy_block quote current
  private="$(private_root)"; public="$(public_root)"; [[ ! -e "${public}/manifest.json" ]] || die 'public manifest already exists'
  # Verify has no approval argument, but it still binds the same immutable quote
  # and live environment before it reads or publishes any evidence.
  require_quote "$(<"$(quote_digest_path)")" verify
  quote="$(<"$(quote_path)")"; current="$(fingerprint)"; check_fingerprint "${current}"; [[ "$(fingerprint_identity <<<"${current}")" == "$(jq -cS .rpc_fingerprint_identity <<<"${quote}")" ]] || die 'RPC/channel fingerprint changed'
  assert_phase smoke 5; assert_phase finish 22
  staging="${private}/verify-rpc-$$"; preview="${private}/manifest-preview-$$.json"; mkdir -p "${staging}"; chmod 700 "${staging}"
  while IFS= read -r op; do
    file="$(journal_path "${op}")"; tx="$(jq -er .tx_hash "${file}")"; block="$(jq -er .block_id "${file}")"; response="$(check_tx "${tx}" "${block}")"; forbidden_public_rpc "${response}" && die "forbidden public RPC field in ${op}"; printf '%s\n' "${response}" >"${staging}/${op}.json"; txs="$(jq -c --arg tx "${tx}" '. + [$tx]' <<<"${txs}")"
  done < <(operations)
  [[ "$(jq -r 'length' <<<"${txs}")" == 27 && "$(jq -r 'unique | length' <<<"${txs}")" == 27 ]] || die 'all 27 operation hashes must be unique'
  file="$(journal_path deploy)"; program_id="$(jq -er '.program_id | select(type == "string" and length > 0)' "${file}")"; deploy_tx="$(jq -r .tx_hash "${file}")"; deploy_block="$(jq -r .block_id "${file}")"
  for part in a b; do
    local id claims='[]' init_tx init_block prefund_tx prefund_block fund_tx fund_block
    id="$(jq -er '.id | select(test("^[0-9a-f]{64}$"))' "${private}/distributions/${part}/id.json")"; assert_distribution_id "${part}" "${id}"; ids="$(jq -c --arg id "${id}" '. + [$id]' <<<"${ids}")"
    for n in $(seq -w 1 10); do file="$(journal_path "${part}-claim-${n}")"; tx="$(jq -r .tx_hash "${file}")"; block="$(jq -r .block_id "${file}")"; claims="$(jq -c --argjson index "$((10#${n}))" --arg tx_hash "${tx}" --argjson block_id "${block}" '. + [{index:$index,tx_hash:$tx_hash,block_id:$block_id}]' <<<"${claims}")"; pairs="$(jq -c --arg tx "${tx}" --argjson block "${block}" '. + [[$tx,$block]]' <<<"${pairs}")"; done
    [[ "$(jq -r 'length' <<<"${claims}")" == 10 ]] || die 'invalid claim count'
    for suffix in init prefund fund; do file="$(journal_path "${part}-${suffix}")"; tx="$(jq -r .tx_hash "${file}")"; block="$(jq -r .block_id "${file}")"; case "${suffix}" in init) init_tx="${tx}"; init_block="${block}" ;; prefund) prefund_tx="${tx}"; prefund_block="${block}" ;; fund) fund_tx="${tx}"; fund_block="${block}" ;; esac; done
    distributions="$(jq -c --arg id "${id}" --arg itx "${init_tx}" --argjson ib "${init_block}" --arg ptx "${prefund_tx}" --argjson pb "${prefund_block}" --arg ftx "${fund_tx}" --argjson fb "${fund_block}" --argjson claims "${claims}" '. + [{distribution_id:$id,init:{tx_hash:$itx,block_id:$ib},prefund:{tx_hash:$ptx,block_id:$pb},fund:{tx_hash:$ftx,block_id:$fb},claims:$claims}]' <<<"${distributions}")"
  done
  [[ "$(jq -r 'unique | length' <<<"${ids}")" == 2 && "$(jq -r 'unique | length' <<<"${pairs}")" == 20 ]] || die 'distribution IDs or claim pairs are not distinct'
  jq -n --arg schema distributionx-lp0003-evidence-v1 --arg source "$(jq -r .execution_source_commit <<<"${quote}")" --arg verifier "$(git -C "${ROOT}" rev-parse HEAD)" --arg tag "$(jq -r .release_tag <<<"${quote}")" --arg lez "$(jq -r .lez_commit <<<"${quote}")" --arg cli_sha256 "$(jq -r .distributionx_cli_sha256 <<<"${quote}")" --arg program_id "${program_id}" --arg tx "${deploy_tx}" --argjson block "${deploy_block}" --argjson fingerprint "${current}" --argjson distributions "${distributions}" --arg quote_sha256 "$(<"$(quote_digest_path)")" '{schema_version:$schema,execution_source_commit:$source,verification_source_commit:$verifier,release_tag:$tag,planned_release_tag:$tag,lez_commit:$lez,distributionx_cli_sha256:$cli_sha256,rpc_fingerprint:$fingerprint,program_id:$program_id,program:{program_id:$program_id,deploy_tx_hash:$tx,deploy_block_id:$block},distributions:$distributions,write_counts:{smoke:5,finish:22,total:27},quote_sha256:$quote_sha256,custom_token_settlement:false,close:false}' >"${preview}"
  forbidden_public "$(<"${preview}")" && die 'manifest has forbidden public field'
  mkdir -p "${public}/rpc"; chmod 755 "${public}" "${public}/rpc"; cp "${staging}"/*.json "${public}/rpc/"; mv "${preview}" "${public}/manifest.json"
}

case "${1:-}" in
  -h|--help|help|'') usage ;;
  prepare) shift; [[ $# -eq 0 ]] || die 'prepare takes no arguments'; prepare ;;
  smoke) shift; smoke "$@" ;;
  finish) shift; finish "$@" ;;
  verify) shift; verify "$@" ;;
  *) usage >&2; exit 64 ;;
esac
