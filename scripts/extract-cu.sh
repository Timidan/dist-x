#!/usr/bin/env bash
set -euo pipefail

# Regenerate the LEZ-sequencer CU table in docs/bench/REPORT.md (between the
# <!-- BEGIN cu-table --> / <!-- END cu-table --> markers) from receipt JSONs
# at target/distributionx-testnet/receipts/<op>.json. Idempotent. Receipt
# schema: {"tx_id": "<hex>", "cu": <integer>, "status": "OK"|"ERROR"}.
# Missing receipts show as "pending"; the script is safe to run repeatedly.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

REPORT="${ROOT}/docs/bench/REPORT.md"
RECEIPTS_DIR="${DISTRIBUTIONX_RECEIPTS_DIR:-${ROOT}/target/distributionx-testnet/receipts}"
OPS=(init_airdrop fund claim close)

[[ -f "${REPORT}" ]] || { echo "missing ${REPORT}" >&2; exit 2; }

read_field() {
  # read_field <file> <jq-expr> — returns "pending" if the file is missing or
  # the field is null/empty.
  local file="$1"; local expr="$2"
  if [[ ! -f "${file}" ]]; then
    echo "pending"; return
  fi
  local value
  value="$(jq -r "${expr} // empty" "${file}" 2>/dev/null || true)"
  if [[ -z "${value}" || "${value}" == "null" ]]; then
    echo "pending"
  else
    echo "${value}"
  fi
}

# Build the new table.
table_lines=()
table_lines+=("| Operation | Tx id | Receipt file | Status | CU |")
table_lines+=("|---|---|---|---|---:|")
for op in "${OPS[@]}"; do
  receipt="${RECEIPTS_DIR}/${op}.json"
  rel_receipt="${receipt#${ROOT}/}"
  tx_id="$(read_field "${receipt}" .tx_id)"
  status="$(read_field "${receipt}" .status)"
  cu="$(read_field "${receipt}" .cu)"
  table_lines+=("| \`${op}\` on standalone LEZ | ${tx_id} | \`${rel_receipt}\` | ${status} | ${cu} |")
done

new_table=$(printf '%s\n' "${table_lines[@]}")

# Splice between markers. If markers are missing, append them at the end of the
# "LEZ Sequencer Measurements" section (one-shot bootstrap).
if ! grep -q "<!-- BEGIN cu-table -->" "${REPORT}"; then
  cat >> "${REPORT}" <<EOF

<!-- BEGIN cu-table -->
${new_table}
<!-- END cu-table -->
EOF
  echo "wrote new cu-table block to ${REPORT}"
  exit 0
fi

tmp="$(mktemp)"
awk -v table="${new_table}" '
  /<!-- BEGIN cu-table -->/ { print; print table; in_block=1; next }
  /<!-- END cu-table -->/   { in_block=0 }
  !in_block { print }
' "${REPORT}" > "${tmp}"
mv "${tmp}" "${REPORT}"
echo "updated cu-table in ${REPORT}"
