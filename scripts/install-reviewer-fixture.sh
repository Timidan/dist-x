#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="${DISTRIBUTIONX_REVIEWER_FIXTURE_DIR:-${ROOT}/fixtures/reviewer-fast-path}"
STATE_DIR="${DISTRIBUTIONX_STATE_DIR:-${ROOT}/target/distributionx-testnet}"

if [[ ! -d "${FIXTURE_DIR}" ]]; then
  echo "E_DISTRIBUTIONX_FIXTURE_MISSING: ${FIXTURE_DIR}" >&2
  exit 1
fi

mkdir -p "${STATE_DIR}/claimants"

cp "${FIXTURE_DIR}/eligible.csv" "${STATE_DIR}/eligible.csv"
cp "${FIXTURE_DIR}/admin.seed" "${STATE_DIR}/admin.seed"
cp "${FIXTURE_DIR}/wallet.seed" "${STATE_DIR}/wallet.seed"
cp "${FIXTURE_DIR}/shielded_destination.json" "${STATE_DIR}/shielded_destination.json"
cp "${FIXTURE_DIR}/claim_destination_commitment.txt" "${STATE_DIR}/claim_destination_commitment.txt"
cp "${FIXTURE_DIR}/fixture-keys.json" "${STATE_DIR}/fixture-keys.json"
cp "${FIXTURE_DIR}"/claimants/*.seed "${STATE_DIR}/claimants/"

admin_account="$(jq -r '.admin.account' "${STATE_DIR}/fixture-keys.json")"
claimant_count="$(jq -r '.claimant_count // (.claimants | length)' "${STATE_DIR}/fixture-keys.json")"

jq -n \
  --arg status "SAMPLE_FIXTURE_OK" \
  --arg source "reviewer-fast-path" \
  --arg state_dir "${STATE_DIR}" \
  --arg admin_account "${admin_account}" \
  --argjson claimant_count "${claimant_count}" \
  '{
    status: $status,
    source: $source,
    state_dir: $state_dir,
    admin_account: $admin_account,
    claimant_count: $claimant_count
  }'
