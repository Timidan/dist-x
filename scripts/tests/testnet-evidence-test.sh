#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="${ROOT}/scripts/testnet-evidence.sh"
mkdir -p "${ROOT}/target"
TEST_ROOT="$(mktemp -d "${ROOT}/target/testnet-evidence-test.XXXXXX")"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

fail() {
  printf 'testnet-evidence-test: %s\n' "$*" >&2
  exit 1
}

expect_fail() {
  local label="$1"
  shift
  if "$@" >"${TEST_ROOT}/${label}.out" 2>&1; then
    fail "${label} unexpectedly succeeded"
  fi
}

expect_fail_matching() {
  local label="$1" pattern="$2"
  shift 2
  expect_fail "${label}" "$@"
  grep -F -- "${pattern}" "${TEST_ROOT}/${label}.out" >/dev/null \
    || fail "${label} did not reach expected guard: ${pattern}"
}

rejection_failures=()
expect_rejection() {
  local label="$1" pattern="$2"
  shift 2
  if "$@" >"${TEST_ROOT}/${label}.out" 2>&1; then
    rejection_failures+=("${label}: unexpectedly succeeded")
  elif ! grep -F -- "${pattern}" "${TEST_ROOT}/${label}.out" >/dev/null; then
    rejection_failures+=("${label}: did not reach expected guard: ${pattern}")
  fi
}

assert_no_writes() {
  [[ ! -s "${WRITE_LOG}" ]] || fail "a read-only/rejected phase invoked a public write"
}

make_hash() {
  printf '%064x' "$1"
}

FAKE_BIN="${TEST_ROOT}/fake-bin"
CONTROL="${TEST_ROOT}/control"
STATE_BASE="${TEST_ROOT}/state"
WRITE_LOG="${CONTROL}/writes.log"
mkdir -p "${FAKE_BIN}" "${CONTROL}" "${STATE_BASE}" "${TEST_ROOT}/lez/.git"

cat >"${FAKE_BIN}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
root="${DISTRIBUTIONX_EVIDENCE_TEST_ROOT:?}"
repo=""
if [[ "${1:-}" == "-C" ]]; then
  repo="$2"
  shift 2
fi
case "${1:-} ${2:-}" in
  "rev-parse HEAD")
    if [[ "${repo}" == "${root}/lez" ]]; then
      printf '%s\n' '47eba256479f6f785acbd138834340703cd03401'
    else
      printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    fi
    ;;
  "rev-parse -q") exit 1 ;;
  "diff --quiet")
    if [[ "${repo}" != "${root}/lez" && "${FAKE_GIT_DIRTY:-0}" == "1" ]]; then
      exit 1
    fi
    ;;
  "ls-files --others")
    if [[ "${repo}" != "${root}/lez" && "${FAKE_GIT_DIRTY:-0}" == "1" ]]; then
      printf '%s\n' dirty-source.txt
    fi
    ;;
  *)
    printf 'unexpected fake git invocation:' >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
    exit 97
    ;;
esac
EOF

cat >"${FAKE_BIN}/fingerprint" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "--rpc" && "${2:-}" == "${LEZ_RPC_URL}" ]] || exit 88
jq -n '{
  rpc_url:env.LEZ_RPC_URL,
  observed_at:"2026-08-13T10:00:00Z",
  healthy:true,
  channel_id:("c" * 64),
  last_block_id:900,
  program_ids:{fake:[1,2,3]},
  compatibility:{
    builtins_match:true,
    latest_matching_release:"v0.2.4",
    pinned_commit:"47eba256479f6f785acbd138834340703cd03401",
    exact_server_version_confirmed:false
  }
}'
EOF

cat >"${FAKE_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
data=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --data) data="$2"; shift 2 ;;
    *) shift ;;
  esac
done
hash="$(jq -er '.params[0]' <<<"${data}")"
mode="ok"
[[ ! -f "${DISTRIBUTIONX_EVIDENCE_TEST_CONTROL}/rpc-mode" ]] \
  || mode="$(<"${DISTRIBUTIONX_EVIDENCE_TEST_CONTROL}/rpc-mode")"
if [[ "${mode}" == "null" ]]; then
  jq -nc '{jsonrpc:"2.0",id:1,result:null}'
  exit 0
fi
suffix="${hash: -8}"
number=$((16#${suffix}))
block=$((1000 + number))
if [[ "${mode}" == "block-mismatch" ]]; then
  block=$((block + 1))
fi
if [[ "${mode}" == "forbidden" ]]; then
  jq -nc --arg hash "${hash}" --argjson block "${block}" \
    '{jsonrpc:"2.0",id:1,result:[{transaction_hash:$hash,private_claim:{salt:"do-not-publish"}},$block]}'
elif [[ "${mode}" == "forbidden-value" ]]; then
  jq -nc --arg hash "${hash}" --argjson block "${block}" \
    '{jsonrpc:"2.0",id:1,result:[{transaction_hash:$hash,status:"included",memo:"wallet.seed: do-not-publish"},$block]}'
elif [[ "${mode}" == "forbidden-nested-array" ]]; then
  jq -nc --arg hash "${hash}" --argjson block "${block}" \
    '{jsonrpc:"2.0",id:1,result:[{transaction_hash:$hash,status:"included",metadata:{items:["safe",["target/private/wallet.seed"]]}},$block]}'
else
  jq -nc --arg hash "${hash}" --argjson block "${block}" \
    '{jsonrpc:"2.0",id:1,result:[{transaction_hash:$hash,status:"included"},$block]}'
fi
EOF

cat >"${FAKE_BIN}/deploy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "--testnet" ]] || exit 91
control="${DISTRIBUTIONX_EVIDENCE_TEST_CONTROL:?}"
[[ -n "${DISTRIBUTIONX_CLI:-}" && -n "${DISTRIBUTIONX_EVIDENCE_CLI_SHA256:-}" ]] || exit 92
[[ "$(sha256sum "${DISTRIBUTIONX_CLI}" | awk '{print $1}')" == "${DISTRIBUTIONX_EVIDENCE_CLI_SHA256}" ]] || exit 93
wallet_config="${DISTRIBUTIONX_EVIDENCE_WALLET_CONFIG:?}"
jq -e --arg rpc "${LEZ_RPC_URL}" \
  '.sequencers == [{sequencer_addr:$rpc,basic_auth:null}]' "${wallet_config}" >/dev/null || exit 94
printf '%s\n' "${wallet_config}" >"${control}/wallet-config-seen"
counter="$(<"${control}/tx-counter")"
counter=$((counter + 1))
printf '%s\n' "${counter}" >"${control}/tx-counter"
hash="$(printf '%064x' "${counter}")"
block=$((1000 + counter))
mismatch=""
[[ ! -f "${control}/deploy-mismatch" ]] || mismatch="$(<"${control}/deploy-mismatch")"
program_id="$(printf 'f%.0s' {1..64})"
deploy_tx_hash="${hash}"
case "${mismatch}" in
  "") printf 'deploy %s %s\n' "${hash}" "${block}" >>"${control}/writes.log" ;;
  program-id) program_id="$(printf 'e%.0s' {1..64})" ;;
  tx-hash) deploy_tx_hash="$(printf 'd%.0s' {1..64})" ;;
  *) exit 95 ;;
esac
mkdir -p "${DISTRIBUTIONX_STATE_DIR}"
jq -n --arg program_id "${program_id}" --arg program_image_id_hex "$(printf 'f%.0s' {1..64})" \
  --arg tx "${deploy_tx_hash}" --arg deterministic_tx_hash "${hash}" --arg rpc "${LEZ_RPC_URL}" --argjson block "${block}" \
  --arg lez_commit '47eba256479f6f785acbd138834340703cd03401' \
  '{status:"DEPLOY_TESTNET_OK",rpc_url:$rpc,program_id:$program_id,program_image_id_hex:$program_image_id_hex,deploy_tx_hash:$tx,deterministic_program_deployment_tx_hash:$deterministic_tx_hash,deploy_block_id:$block,deploy_signer_account:null,lez_commit:$lez_commit}' \
  >"${DISTRIBUTIONX_STATE_DIR}/deployment.json"
printf 'DEPLOY_TESTNET_OK\n'
EOF

cat >"${FAKE_BIN}/distributionx-cli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
control="${DISTRIBUTIONX_EVIDENCE_TEST_CONTROL:?}"
command_name="${1:-}"
shift || true

next_counter() {
  local file="$1" current
  current="$(<"${control}/${file}")"
  current=$((current + 1))
  printf '%s\n' "${current}" >"${control}/${file}"
  printf '%s\n' "${current}"
}

next_tx() {
  local number
  number="$(next_counter tx-counter)"
  printf '%064x %s\n' "${number}" "$((1000 + number))"
}

arg_value() {
  local wanted="$1"
  shift
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "${wanted}" ]]; then
      printf '%s\n' "$2"
      return 0
    fi
    shift
  done
  return 1
}

assert_write_environment() {
  local op="$1" expected
  expected="bash ${DISTRIBUTIONX_EVIDENCE_REPO_ROOT}/scripts/local-submit.sh ${op}"
  case "${op}" in
    init) [[ "${DISTRIBUTIONX_INIT_SUBMIT_COMMAND:-}" == "${expected}" ]] ;;
    fund) [[ "${DISTRIBUTIONX_FUND_SUBMIT_COMMAND:-}" == "${expected}" ]] ;;
    claim) [[ "${DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND:-}" == "${expected}" ]] ;;
  esac
  [[ "${RISC0_DEV_MODE:-}" == "0" ]]
  [[ "${DISTRIBUTIONX_USE_CUSTOM_TOKEN_SETTLEMENT:-}" == "0" ]]
  [[ "${DISTRIBUTIONX_USE_CLAIM_PRIVATE:-}" == "0" ]]
  [[ -z "${DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT+x}" ]] || {
    echo 'token source account remained exported during write' >&2
    exit 96
  }
  [[ -n "${DISTRIBUTIONX_ENV_FILE:-}" && ! -e "${DISTRIBUTIONX_ENV_FILE}" ]]
}

assert_active_distribution_state() {
  [[ -n "${DISTRIBUTIONX_STATE_DIR:-}" && -n "${DISTRIBUTIONX_RECEIPTS_DIR:-}" ]]
  [[ "${DISTRIBUTIONX_STATE_DIR}" != "${DISTRIBUTIONX_RECEIPTS_DIR}" ]]
  [[ -f "${DISTRIBUTIONX_STATE_DIR}/deployment.json" ]]
}

case "${command_name}" in
  sample-fixture)
    echo 'deterministic sample-fixture is forbidden' >&2
    exit 90
    ;;
  create-wallet)
    out="$(arg_value --out-dir "$@")"
    number="$(next_counter wallet-counter)"
    account="$(printf '%064x' "$((100 + number))")"
    mkdir -p "${out}"
    printf '%064x' "$((1000 + number))" >"${out}/wallet.seed"
    jq -nc --arg account "Public/${account}" --arg path "${out}/wallet.seed" \
      '{status:"CREATE_WALLET_OK",account:$account,wallet_seed_path:$path}'
    ;;
  create-destination)
    out="$(arg_value --out-dir "$@")"
    number="$(next_counter destination-counter)"
    commitment="$(printf '%064x' "$((200 + number))")"
    mkdir -p "${out}"
    printf '%s' "${commitment}" >"${out}/claim_destination_commitment.txt"
    jq -n --arg npk "$(printf '%064x' "$((300 + number))")" \
      --arg vpk "$(printf '%0128x' "$((400 + number))")" \
      '{npk:$npk,vpk:$vpk,identifier_le:("0" * 32)}' \
      >"${out}/shielded_destination.json"
    jq -n --arg secret "$(printf '%064x' "$((500 + number))")" \
      '{secret_spending_key:$secret}' >"${out}/shielded_destination_keys.json"
    jq -nc --arg commitment "${commitment}" \
      '{status:"DESTINATION_CREATED",claim_destination_commitment:$commitment}'
    ;;
  init)
    assert_write_environment init
    assert_active_distribution_state
    if ! token_source_account="$(arg_value --token-source-account "$@")"; then
      echo 'init omitted explicit empty token source account' >&2
      exit 98
    fi
    [[ -z "${token_source_account}" ]] || exit 99
    read -r tx block < <(next_tx)
    printf 'init %s %s\n' "${tx}" "${block}" >>"${control}/writes.log"
    if [[ "${DISTRIBUTIONX_AIRDROP_NAME}" == *-a ]]; then
      distribution_id="$(printf 'a%.0s' {1..64})"
    else
      distribution_id="$(printf 'b%.0s' {1..64})"
    fi
    mkdir -p "${DISTRIBUTIONX_STATE_DIR}/states" "${DISTRIBUTIONX_RECEIPTS_DIR}"
    jq -n --arg name "${DISTRIBUTIONX_AIRDROP_NAME}" --arg id "${distribution_id}" \
      '{name:$name,airdrop_id:$id,total_funded:0,total_claimed:0,nullifiers:[]}' \
      >"${DISTRIBUTIONX_STATE_DIR}/state.json"
    jq -n --arg id "${distribution_id}" '{airdrop_id:$id,encrypted_rows:[]}' \
      >"${DISTRIBUTIONX_STATE_DIR}/bundle.json"
    jq -n --arg tx "${tx}" --argjson block "${block}" \
      '{tx_id:$tx,block_id:$block,status:"OK",token_tx_id:null,vault_prefund_tx_id:null}' \
      >"${DISTRIBUTIONX_RECEIPTS_DIR}/init_airdrop.json"
    jq -nc --arg name "${DISTRIBUTIONX_AIRDROP_NAME}" --arg id "${distribution_id}" --arg tx "${tx}" \
      '{status:"INIT_OK",airdrop:$name,airdrop_id:$id,recipient_count:10,tx_id:$tx}'
    ;;
  fund)
    assert_write_environment fund
    assert_active_distribution_state
    [[ -f "${DISTRIBUTIONX_STATE_DIR}/bundle.json" ]]
    read -r prefund_tx prefund_block < <(next_tx)
    read -r fund_tx fund_block < <(next_tx)
    printf 'prefund %s %s\n' "${prefund_tx}" "${prefund_block}" >>"${control}/writes.log"
    printf 'fund %s %s\n' "${fund_tx}" "${fund_block}" >>"${control}/writes.log"
    mkdir -p "${DISTRIBUTIONX_RECEIPTS_DIR}"
    jq -n --arg tx "${fund_tx}" --argjson block "${fund_block}" \
      --arg prefund "${prefund_tx}" --argjson prefund_block "${prefund_block}" \
      '{tx_id:$tx,block_id:$block,status:"OK",token_tx_id:null,vault_prefund_tx_id:$prefund,vault_prefund_block_id:$prefund_block}' \
      >"${DISTRIBUTIONX_RECEIPTS_DIR}/fund.json"
    jq -nc --arg tx "${fund_tx}" '{status:"FUND_OK",amount:10,total_funded:10,tx_id:$tx}'
    ;;
  prepare-claim-tx)
    assert_active_distribution_state
    bundle="$(arg_value --bundle "$@")"
    [[ "${bundle}" == "${DISTRIBUTIONX_STATE_DIR}/bundle.json" && -f "${bundle}" ]]
    out="$(arg_value --out "$@")"
    mkdir -p "$(dirname "${out}")"
    jq -n '{private_claim:{claimant_address:("1" * 64),salt:("2" * 64),merkle_siblings:[]},recipient_npk:("3" * 64)}' >"${out}"
    jq -nc --arg out "${out}" '{status:"PREPARE_CLAIM_TX_OK",serialized_lez_tx:$out}'
    ;;
  claim)
    assert_write_environment claim
    assert_active_distribution_state
    [[ -f "${DISTRIBUTIONX_STATE_DIR}/bundle.json" ]]
    read -r tx block < <(next_tx)
    printf 'claim %s %s\n' "${tx}" "${block}" >>"${control}/writes.log"
    mkdir -p "${DISTRIBUTIONX_RECEIPTS_DIR}"
    jq -n --arg tx "${tx}" --argjson block "${block}" \
      '{tx_id:$tx,block_id:$block,status:"OK",token_tx_id:null,vault_prefund_tx_id:null}' \
      >"${DISTRIBUTIONX_RECEIPTS_DIR}/claim.json"
    jq -nc --arg tx "${tx}" '{status:"CLAIM_OK",amount:1,tx_id:$tx,token_tx_id:null}'
    ;;
  *)
    echo "unexpected fake CLI command: ${command_name}" >&2
    exit 89
    ;;
esac
EOF

chmod +x "${FAKE_BIN}/git" "${FAKE_BIN}/fingerprint" "${FAKE_BIN}/curl" \
  "${FAKE_BIN}/deploy" "${FAKE_BIN}/distributionx-cli"
printf '0\n' >"${CONTROL}/tx-counter"
printf '0\n' >"${CONTROL}/wallet-counter"
printf '0\n' >"${CONTROL}/destination-counter"

export PATH="${FAKE_BIN}:${PATH}"
export DISTRIBUTIONX_EVIDENCE_TEST_ROOT="${TEST_ROOT}"
export DISTRIBUTIONX_EVIDENCE_TEST_CONTROL="${CONTROL}"
export DISTRIBUTIONX_EVIDENCE_REPO_ROOT="${ROOT}"
export DISTRIBUTIONX_EVIDENCE_STATE_BASE="${STATE_BASE}"
export DISTRIBUTIONX_EVIDENCE_FINGERPRINT_SCRIPT="${FAKE_BIN}/fingerprint"
export DISTRIBUTIONX_EVIDENCE_DEPLOY_SCRIPT="${FAKE_BIN}/deploy"
export DISTRIBUTIONX_CLI="${FAKE_BIN}/distributionx-cli"
export DISTRIBUTIONX_LEZ_REPO="${TEST_ROOT}/lez"
export DISTRIBUTIONX_EVIDENCE_REGRESSION_TEST=1
export LEZ_RPC_URL="https://rpc.example.invalid"
export LEZ_DEPLOYER_WALLET="Public/$(make_hash 700)"
export DISTRIBUTIONX_RECOVERY_ADDRESS="Public/$(make_hash 701)"
export DISTRIBUTIONX_TOKEN_ID="$(make_hash 702)"
export DISTRIBUTIONX_EXPIRY_UNIX=1924992000
export DISTRIBUTIONX_RELAYER_URL="https://relayer.example.invalid"
export RISC0_DEV_MODE=0

bash "${HELPER}" --help >"${TEST_ROOT}/help.out"
assert_no_writes

expect_rejection production-noncanonical-overrides \
  'production mode forbids noncanonical evidence path overrides' \
  env -u DISTRIBUTIONX_EVIDENCE_REGRESSION_TEST \
    DISTRIBUTIONX_EVIDENCE_RUN_ID=lp0003-production-override-test \
    DISTRIBUTIONX_RELEASE_TAG=v9.9.1-production-override \
    bash "${HELPER}" prepare
assert_no_writes

expect_rejection production-inherited-deploy-command \
  'production evidence forbids inherited deployment overrides' \
  env -u DISTRIBUTIONX_EVIDENCE_REGRESSION_TEST \
    -u DISTRIBUTIONX_EVIDENCE_REPO_ROOT -u DISTRIBUTIONX_CLI \
    -u DISTRIBUTIONX_EVIDENCE_FINGERPRINT_SCRIPT -u DISTRIBUTIONX_EVIDENCE_DEPLOY_SCRIPT \
    -u DISTRIBUTIONX_LEZ_REPO -u DISTRIBUTIONX_EVIDENCE_STATE_BASE \
    LEZ_DEPLOY_COMMAND=auto bash "${HELPER}" --help
expect_rejection production-inherited-wallet-bin \
  'production evidence forbids inherited deployment overrides' \
  env -u DISTRIBUTIONX_EVIDENCE_REGRESSION_TEST \
    -u DISTRIBUTIONX_EVIDENCE_REPO_ROOT -u DISTRIBUTIONX_CLI \
    -u DISTRIBUTIONX_EVIDENCE_FINGERPRINT_SCRIPT -u DISTRIBUTIONX_EVIDENCE_DEPLOY_SCRIPT \
    -u DISTRIBUTIONX_LEZ_REPO -u DISTRIBUTIONX_EVIDENCE_STATE_BASE \
    LEZ_WALLET_BIN=/tmp/fake-wallet bash "${HELPER}" --help
expect_rejection production-inherited-wallet-home \
  'production evidence forbids inherited deployment overrides' \
  env -u DISTRIBUTIONX_EVIDENCE_REGRESSION_TEST \
    -u DISTRIBUTIONX_EVIDENCE_REPO_ROOT -u DISTRIBUTIONX_CLI \
    -u DISTRIBUTIONX_EVIDENCE_FINGERPRINT_SCRIPT -u DISTRIBUTIONX_EVIDENCE_DEPLOY_SCRIPT \
    -u DISTRIBUTIONX_LEZ_REPO -u DISTRIBUTIONX_EVIDENCE_STATE_BASE \
    LEE_WALLET_HOME_DIR=/tmp/fake-wallet-home bash "${HELPER}" --help
assert_no_writes

expect_rejection regression-live-rpc \
  'regression mode requires an HTTPS .invalid RPC host' \
  env DISTRIBUTIONX_EVIDENCE_RUN_ID=lp0003-regression-live-rpc-test \
    DISTRIBUTIONX_RELEASE_TAG=v9.9.1-regression-live-rpc \
    LEZ_RPC_URL=https://testnet.lez.logos.co \
    bash "${HELPER}" prepare
assert_no_writes

export DISTRIBUTIONX_EVIDENCE_RUN_ID="lp0003-local-rpc-test"
export DISTRIBUTIONX_RELEASE_TAG="v9.9.1-local"
LEZ_RPC_URL="https://localhost/rpc" expect_fail local-rpc bash "${HELPER}" prepare
assert_no_writes

export DISTRIBUTIONX_EVIDENCE_RUN_ID="lp0003-dirty-source-test"
export DISTRIBUTIONX_RELEASE_TAG="v9.9.1-dirty"
FAKE_GIT_DIRTY=1 expect_fail dirty-source bash "${HELPER}" prepare
assert_no_writes

export DISTRIBUTIONX_EVIDENCE_RUN_ID="lp0003-inherited-token-source-test"
export DISTRIBUTIONX_RELEASE_TAG="v9.9.1-token-source"
DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT="Public/$(make_hash 703)" \
  expect_fail_matching inherited-token-source-prepare \
    'token source account must be empty' bash "${HELPER}" prepare
assert_no_writes

RUN_ID="lp0003-fake-evidence-001"
RELEASE_TAG="v9.9.1-evidence"
export DISTRIBUTIONX_EVIDENCE_RUN_ID="${RUN_ID}"
export DISTRIBUTIONX_RELEASE_TAG="${RELEASE_TAG}"
bash "${HELPER}" prepare >"${TEST_ROOT}/prepare.out"
assert_no_writes

RUN_ROOT="${STATE_BASE}/${RUN_ID}"
PRIVATE_ROOT="${RUN_ROOT}/private"
PUBLIC_ROOT="${RUN_ROOT}/public"
QUOTE_DIGEST="$(<"${PRIVATE_ROOT}/quote.sha256")"
[[ "${QUOTE_DIGEST}" =~ ^[0-9a-f]{64}$ ]] || fail "prepare did not emit a quote digest"
[[ "$(find "${PRIVATE_ROOT}/claimants" -type f -name wallet.seed | wc -l)" == "20" ]] \
  || fail "prepare did not create 20 wallet slots"
[[ "$(find "${PRIVATE_ROOT}/claimants" -type f -name shielded_destination.json | wc -l)" == "20" ]] \
  || fail "prepare did not create 20 destination slots"
[[ "$(tail -n +2 "${PRIVATE_ROOT}/distributions/a/eligible.csv" | wc -l)" == "10" ]] \
  || fail "distribution A CSV does not have 10 rows"
[[ "$(tail -n +2 "${PRIVATE_ROOT}/distributions/b/eligible.csv" | wc -l)" == "10" ]] \
  || fail "distribution B CSV does not have 10 rows"
[[ "$( { tail -n +2 "${PRIVATE_ROOT}/distributions/a/eligible.csv"; tail -n +2 "${PRIVATE_ROOT}/distributions/b/eligible.csv"; } \
  | cut -d, -f1 | sort -u | wc -l)" == "20" ]] \
  || fail "claim wallets are not all distinct"
jq -e '.write_counts == {smoke:5,finish:22,total:27} and .claim_amount_raw == 1 and .distribution_funding_raw == 10 and .deployer.already_funded_assumption == true and .deployer.initialization_or_funding_in_scope == false' \
  "${PRIVATE_ROOT}/quote.json" >/dev/null || fail "quote counts or deployer assumption are wrong"
CLI_SHA256="$(sha256sum "${FAKE_BIN}/distributionx-cli" | awk '{print $1}')"
jq -e --arg cli_sha256 "${CLI_SHA256}" '.distributionx_cli_sha256 == $cli_sha256' \
  "${PRIVATE_ROOT}/quote.json" >/dev/null || fail "quote does not bind the CLI hash"
jq -e --arg rpc "${LEZ_RPC_URL}" \
  '.sequencers == [{sequencer_addr:$rpc,basic_auth:null}]' \
  "${PRIVATE_ROOT}/wallet/wallet_config.json" >/dev/null \
  || fail "prepare did not bind the private wallet config to the quoted RPC"
[[ "$(stat -c %a "${PRIVATE_ROOT}")" == "700" ]] || fail "private root is not mode 0700"
if find "${PRIVATE_ROOT}" -type d ! -perm 0700 -print -quit | grep -q .; then
  fail "a private directory is not mode 0700"
fi
if find "${PRIVATE_ROOT}" -type f ! -perm 0600 -print -quit | grep -q .; then
  fail "a private file is not mode 0600"
fi

expect_fail smoke-missing-digest bash "${HELPER}" smoke
assert_no_writes
expect_fail smoke-wrong-digest bash "${HELPER}" smoke "$(make_hash 999)"
assert_no_writes

DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT="Public/$(make_hash 704)" \
  expect_fail_matching inherited-token-source-smoke \
    'token source account must be empty' bash "${HELPER}" smoke "${QUOTE_DIGEST}"
assert_no_writes

quote_backup="${TEST_ROOT}/quote.json"
cp "${PRIVATE_ROOT}/quote.json" "${quote_backup}"
jq '.release_tag="v0.0.0"' "${quote_backup}" >"${PRIVATE_ROOT}/quote.json"
expect_fail_matching quote-tamper 'quote digest is not immutable' bash "${HELPER}" smoke "${QUOTE_DIGEST}"
cp "${quote_backup}" "${PRIVATE_ROOT}/quote.json"
LEZ_RPC_URL="https://rpc-drift.example.invalid" expect_fail_matching rpc-drift 'RPC/channel fingerprint changed' bash "${HELPER}" smoke "${QUOTE_DIGEST}"
FAKE_GIT_DIRTY=1 expect_fail_matching source-drift 'source tree is dirty' bash "${HELPER}" smoke "${QUOTE_DIGEST}"
DISTRIBUTIONX_RELEASE_TAG=v9.9.2-drift expect_fail_matching env-drift 'runtime differs from approved quote' bash "${HELPER}" smoke "${QUOTE_DIGEST}"
assert_no_writes

for mismatch in program-id tx-hash; do
  MISMATCH_RUN_ID="lp0003-${mismatch}-mismatch-test"
  export DISTRIBUTIONX_EVIDENCE_RUN_ID="${MISMATCH_RUN_ID}"
  export DISTRIBUTIONX_RELEASE_TAG="v9.9.1-${mismatch}-mismatch"
  bash "${HELPER}" prepare >"${TEST_ROOT}/${mismatch}-prepare.out"
  mismatch_private="${STATE_BASE}/${MISMATCH_RUN_ID}/private"
  mismatch_quote="$(<"${mismatch_private}/quote.sha256")"
  printf '%s\n' "${mismatch}" >"${CONTROL}/deploy-mismatch"
  expect_rejection "deploy-${mismatch}-mismatch" 'invalid deploy receipt' \
    bash "${HELPER}" smoke "${mismatch_quote}"
  rm -f "${CONTROL}/deploy-mismatch"
  assert_no_writes
  rm -rf -- "${STATE_BASE}/${MISMATCH_RUN_ID}"
done

export DISTRIBUTIONX_EVIDENCE_RUN_ID="${RUN_ID}"
export DISTRIBUTIONX_RELEASE_TAG="${RELEASE_TAG}"

export DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT=""
bash "${HELPER}" smoke "${QUOTE_DIGEST}" >"${TEST_ROOT}/smoke.out"
unset DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT
[[ "$(wc -l <"${WRITE_LOG}")" == "5" ]] || fail "smoke did not execute exactly five writes"
jq -e --arg rpc "${LEZ_RPC_URL}" \
  '.sequencers == [{sequencer_addr:$rpc,basic_auth:null}]' \
  "$(<"${CONTROL}/wallet-config-seen")" >/dev/null \
  || fail "fake deployment did not receive a wallet config bound to the quoted RPC"
jq -e '.write_count == 5 and .complete == true' "${PRIVATE_ROOT}/phases/smoke.json" >/dev/null \
  || fail "smoke completion marker is invalid"

smoke_receipt="${PRIVATE_ROOT}/receipts/a-claim-01/claim.json"
smoke_receipt_backup="${TEST_ROOT}/smoke-claim.json"
cp "${smoke_receipt}" "${smoke_receipt_backup}"
jq --arg tx "$(make_hash 996)" '.tx_id=$tx' "${smoke_receipt_backup}" >"${smoke_receipt}"
expect_fail_matching completed-smoke-revalidation 'journal/receipt mismatch' bash "${HELPER}" smoke "${QUOTE_DIGEST}"
cp "${smoke_receipt_backup}" "${smoke_receipt}"

a_state_deployment="${PRIVATE_ROOT}/distributions/a/state/deployment.json"
a_state_deployment_backup="${TEST_ROOT}/a-state-deployment.json"
cp "${a_state_deployment}" "${a_state_deployment_backup}"
rm "${a_state_deployment}"
expect_fail_matching missing-a-state-deployment 'missing persistent deployment state after init' \
  env -u DISTRIBUTIONX_STATE_DIR bash "${HELPER}" finish "${QUOTE_DIGEST}"
[[ "$(wc -l <"${WRITE_LOG}")" == "5" ]] || fail "missing A state caused a rebroadcast"
cp "${a_state_deployment_backup}" "${a_state_deployment}"
jq '.program_id="tampered"' "${a_state_deployment_backup}" >"${a_state_deployment}"
expect_fail_matching tampered-a-state-deployment 'state deployment receipt mismatch' \
  env -u DISTRIBUTIONX_STATE_DIR bash "${HELPER}" finish "${QUOTE_DIGEST}"
[[ "$(wc -l <"${WRITE_LOG}")" == "5" ]] || fail "tampered A state caused a rebroadcast"
cp "${a_state_deployment_backup}" "${a_state_deployment}"

mkdir "${PRIVATE_ROOT}/receipts/a-claim-02"
expect_fail_matching partial-receipt 'receipt exists without journal' bash "${HELPER}" finish "${QUOTE_DIGEST}"
[[ "$(wc -l <"${WRITE_LOG}")" == "5" ]] || fail "partial receipt caused a rebroadcast"
rmdir "${PRIVATE_ROOT}/receipts/a-claim-02"

expect_fail finish-missing-digest bash "${HELPER}" finish
[[ "$(wc -l <"${WRITE_LOG}")" == "5" ]] || fail "missing finish digest invoked a command"
expect_fail finish-wrong-digest bash "${HELPER}" finish "$(make_hash 998)"
[[ "$(wc -l <"${WRITE_LOG}")" == "5" ]] || fail "wrong finish digest invoked a command"

# B has not been initialized yet, so removing its bootstrap receipt is the one
# allowed recovery case: finish must recreate it from the validated deployment.
rm "${PRIVATE_ROOT}/distributions/b/state/deployment.json"
env -u DISTRIBUTIONX_STATE_DIR bash "${HELPER}" finish "${QUOTE_DIGEST}" >"${TEST_ROOT}/finish.out"
[[ "$(wc -l <"${WRITE_LOG}")" == "27" ]] || fail "full run did not execute exactly 27 writes"
jq -e '.write_count == 22 and .complete == true' "${PRIVATE_ROOT}/phases/finish.json" >/dev/null \
  || fail "finish completion marker is invalid"
jq -e '.id == ("a" * 64)' "${PRIVATE_ROOT}/distributions/a/id.json" >/dev/null \
  || fail "distribution A id was null or incorrect"
jq -e '.id == ("b" * 64)' "${PRIVATE_ROOT}/distributions/b/id.json" >/dev/null \
  || fail "distribution B id was null or incorrect"

claim_two="${PRIVATE_ROOT}/journal/a-claim-02.json"
claim_two_backup="${TEST_ROOT}/a-claim-02.json"
cp "${claim_two}" "${claim_two_backup}"
claim_one_hash="$(jq -r '.tx_hash' "${PRIVATE_ROOT}/journal/a-claim-01.json")"
jq --arg tx "${claim_one_hash}" '.tx_hash=$tx' "${claim_two_backup}" >"${claim_two}"
expect_fail_matching duplicate-hash 'journal/receipt mismatch' bash "${HELPER}" verify
cp "${claim_two_backup}" "${claim_two}"

deploy_journal="${PRIVATE_ROOT}/journal/deploy.json"
deploy_journal_backup="${TEST_ROOT}/deploy-journal.json"
cp "${deploy_journal}" "${deploy_journal_backup}"
jq '.program_id="not-the-deployed-program"' "${deploy_journal_backup}" >"${deploy_journal}"
expect_fail_matching deploy-program-journal-tamper 'deploy journal/receipt program mismatch' bash "${HELPER}" verify
cp "${deploy_journal_backup}" "${deploy_journal}"

a_id="${PRIVATE_ROOT}/distributions/a/id.json"
a_id_backup="${TEST_ROOT}/a-id.json"
cp "${a_id}" "${a_id_backup}"
jq --arg id "$(make_hash 995)" '.id=$id' "${a_id_backup}" >"${a_id}"
expect_fail_matching distribution-id-tamper 'distribution id/state mismatch' bash "${HELPER}" verify
cp "${a_id_backup}" "${a_id}"

# Keep the altered receipt internally consistent so verification reaches the
# all-27 uniqueness invariant rather than stopping at receipt reconciliation.
b_fund_receipt="${PRIVATE_ROOT}/receipts/b-fund/fund.json"
b_fund_receipt_backup="${TEST_ROOT}/b-fund-receipt.json"
b_fund_journal_backup="${TEST_ROOT}/b-fund-journal.json"
cp "${b_fund_receipt}" "${b_fund_receipt_backup}"
cp "${PRIVATE_ROOT}/journal/b-fund.json" "${b_fund_journal_backup}"
a_fund_tx="$(jq -r '.tx_hash' "${PRIVATE_ROOT}/journal/a-fund.json")"
a_fund_block="$(jq -r '.block_id' "${PRIVATE_ROOT}/journal/a-fund.json")"
jq --arg tx "${a_fund_tx}" --argjson block "${a_fund_block}" '.tx_hash=$tx | .block_id=$block' \
  "${PRIVATE_ROOT}/journal/b-fund.json" >"${TEST_ROOT}/b-fund-duplicate.json"
mv "${TEST_ROOT}/b-fund-duplicate.json" "${PRIVATE_ROOT}/journal/b-fund.json"
jq --arg tx "${a_fund_tx}" --argjson block "${a_fund_block}" '.tx_id=$tx | .block_id=$block' \
  "${b_fund_receipt_backup}" >"${b_fund_receipt}"
expect_fail_matching all-27-duplicate 'all 27 operation hashes must be unique' bash "${HELPER}" verify
cp "${b_fund_journal_backup}" "${PRIVATE_ROOT}/journal/b-fund.json"
cp "${b_fund_receipt_backup}" "${b_fund_receipt}"

fund_journal="${PRIVATE_ROOT}/journal/b-fund.json"
fund_backup="${TEST_ROOT}/b-fund.json"
cp "${fund_journal}" "${fund_backup}"
jq '.tx_hash=""' "${fund_backup}" >"${fund_journal}"
expect_fail missing-hash bash "${HELPER}" verify
cp "${fund_backup}" "${fund_journal}"

printf 'null\n' >"${CONTROL}/rpc-mode"
expect_fail null-transaction bash "${HELPER}" verify
printf 'block-mismatch\n' >"${CONTROL}/rpc-mode"
expect_fail block-mismatch bash "${HELPER}" verify
rm -f "${CONTROL}/rpc-mode"

claim_receipt="${PRIVATE_ROOT}/receipts/a-claim-01/claim.json"
claim_receipt_backup="${TEST_ROOT}/a-claim-01-receipt.json"
cp "${claim_receipt}" "${claim_receipt_backup}"
jq --arg tx "$(make_hash 997)" '.tx_id=$tx' "${claim_receipt_backup}" >"${claim_receipt}"
expect_fail_matching receipt-tamper 'journal/receipt mismatch' bash "${HELPER}" verify
cp "${claim_receipt_backup}" "${claim_receipt}"

printf 'forbidden\n' >"${CONTROL}/rpc-mode"
expect_fail forbidden-public-field bash "${HELPER}" verify
rm -f "${CONTROL}/rpc-mode"
[[ ! -e "${PUBLIC_ROOT}/manifest.json" ]] \
  || fail "verify published a manifest after seeing a forbidden RPC field"

printf 'forbidden-value\n' >"${CONTROL}/rpc-mode"
expect_fail forbidden-public-value bash "${HELPER}" verify
rm -f "${CONTROL}/rpc-mode"
[[ ! -e "${PUBLIC_ROOT}/manifest.json" ]] \
  || fail "verify published a manifest after seeing forbidden value material"

printf 'forbidden-nested-array\n' >"${CONTROL}/rpc-mode"
expect_fail forbidden-public-nested-array bash "${HELPER}" verify
rm -f "${CONTROL}/rpc-mode"
[[ ! -e "${PUBLIC_ROOT}/manifest.json" ]] \
  || fail "verify published a manifest after nested forbidden value material"

bash "${HELPER}" verify >"${TEST_ROOT}/verify.out"
MANIFEST="${PUBLIC_ROOT}/manifest.json"
jq -e --arg cli_sha256 "${CLI_SHA256}" '
  .schema_version == "distributionx-lp0003-evidence-v1" and
  .execution_source_commit == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" and
  .planned_release_tag == "v9.9.1-evidence" and
  .lez_commit == "47eba256479f6f785acbd138834340703cd03401" and
  .distributionx_cli_sha256 == $cli_sha256 and
  .program_id == ("f" * 64) and .program.program_id == ("f" * 64) and
  .write_counts == {smoke:5,finish:22,total:27} and
  (.distributions | length) == 2 and
  ([.distributions[].claims[]] | length) == 20 and
  .custom_token_settlement == false and .close == false
' "${MANIFEST}" >/dev/null || fail "manifest does not have the exact required shape/counts"
[[ "$(find "${PUBLIC_ROOT}/rpc" -type f -name '*.json' | wc -l)" == "27" ]] \
  || fail "verify did not publish 27 raw RPC captures"
if grep -ERiq 'wallet[._-]?seed|seed_path|eligible_address|eligibility_row|claimant_address|salt|merkle_(path|siblings)|private_claim|bundle\.json|claim\.tx|shielded_destination|secret_spending_key|recipient_(npk|vpk|identifier)|target/' "${PUBLIC_ROOT}"; then
  fail "public evidence contains secret material"
fi

cli_backup="${TEST_ROOT}/distributionx-cli-before-drift"
cp "${FAKE_BIN}/distributionx-cli" "${cli_backup}"
printf '\n# altered after prepare\n' >>"${FAKE_BIN}/distributionx-cli"
writes_before_cli_drift="$(wc -l <"${WRITE_LOG}")"
expect_rejection cli-hash-drift \
  'distributionx-cli SHA-256 changed' \
  bash "${HELPER}" finish "${QUOTE_DIGEST}"
mv "${cli_backup}" "${FAKE_BIN}/distributionx-cli"
[[ "$(wc -l <"${WRITE_LOG}")" == "${writes_before_cli_drift}" ]] \
  || fail "CLI hash drift invoked a public write"

if ((${#rejection_failures[@]} > 0)); then
  printf 'testnet-evidence-test: regression guards failed:\n' >&2
  printf '%s\n' "${rejection_failures[@]}" >&2
  exit 1
fi

echo "testnet-evidence-test: PASS"
