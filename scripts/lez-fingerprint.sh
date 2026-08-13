#!/usr/bin/env bash
set -euo pipefail

LEZ_V024_COMMIT="47eba256479f6f785acbd138834340703cd03401"
RPC_URL="${LEZ_RPC_URL:-https://testnet.lez.logos.co}"
ENFORCE=1
EXPECTED_CHANNEL_ID=""

usage() {
  cat <<'EOF'
Usage: scripts/lez-fingerprint.sh [--rpc URL] [--expected-channel HEX] [--observe]

Reads only public LEZ JSON-RPC state. By default, it fails unless the built-in
program IDs match the LEZ v0.2.4 compatibility fingerprint used by
DistributionX. --observe prints an unmatched fingerprint without failing.
--expected-channel additionally requires an exact 32-byte channel ID; use it
for a known local genesis configuration.

This proves built-in compatibility, not the sequencer's exact software version;
the current LEZ RPC has no version/commit method.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rpc)
      [[ $# -ge 2 ]] || { echo "E_LEZ_FINGERPRINT_RPC_VALUE_REQUIRED" >&2; exit 64; }
      RPC_URL="$2"
      shift 2
      ;;
    --observe)
      ENFORCE=0
      shift
      ;;
    --expected-channel)
      [[ $# -ge 2 ]] || { echo "E_LEZ_FINGERPRINT_CHANNEL_VALUE_REQUIRED" >&2; exit 64; }
      EXPECTED_CHANNEL_ID="${2,,}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "E_LEZ_FINGERPRINT_UNKNOWN_ARGUMENT: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

for dependency in curl jq; do
  command -v "${dependency}" >/dev/null 2>&1 || {
    echo "E_LEZ_FINGERPRINT_DEPENDENCY_MISSING: ${dependency}" >&2
    exit 2
  }
done

EXPECTED_PROGRAM_IDS='{"amm":[1765802831,3731187220,2062982807,1520762763,307650957,4265115253,384461553,795532917],"authenticated_transfer":[583309054,2344528779,3806558405,2890696795,2257354672,3978764116,2273929063,1518858078],"pinata":[2062635772,3904239712,2833328350,20714435,436307236,2247732790,2681611470,2354246644],"privacy_preserving_circuit":[1334328888,3910590567,1244219104,3671232111,3138827701,405554639,4064616947,1864368340],"token":[1047643340,4291649067,2093396023,4016657193,3904308476,481382041,2987082047,2603530278]}'

rpc_call() {
  local method="$1"
  local request response
  request="$(jq -nc --arg method "${method}" '{jsonrpc:"2.0",id:1,method:$method,params:[]}')"
  response="$(curl --fail-with-body --silent --show-error --max-time 15 \
    --header 'content-type: application/json' \
    --data "${request}" \
    "${RPC_URL}")" || {
      echo "E_LEZ_FINGERPRINT_RPC_UNREACHABLE: method=${method}" >&2
      return 1
    }
  if ! jq -e 'type == "object" and .id == 1 and has("result") and (.error == null)' \
    >/dev/null <<<"${response}"; then
    echo "E_LEZ_FINGERPRINT_RPC_RESPONSE: method=${method} response=${response}" >&2
    return 1
  fi
  jq -c '.result' <<<"${response}"
}

health="$(rpc_call checkHealth)"
[[ "${health}" == "null" ]] || {
  echo "E_LEZ_FINGERPRINT_UNHEALTHY: result=${health}" >&2
  exit 1
}

channel_id="$(rpc_call getChannelId | jq -r '.')"
[[ "${channel_id}" =~ ^[[:xdigit:]]{64}$ ]] || {
  echo "E_LEZ_FINGERPRINT_CHANNEL_ID: ${channel_id}" >&2
  exit 1
}
channel_id="${channel_id,,}"
if [[ -n "${EXPECTED_CHANNEL_ID}" ]]; then
  [[ "${EXPECTED_CHANNEL_ID}" =~ ^[[:xdigit:]]{64}$ ]] || {
    echo "E_LEZ_FINGERPRINT_EXPECTED_CHANNEL_ID: ${EXPECTED_CHANNEL_ID}" >&2
    exit 64
  }
  [[ "${channel_id}" == "${EXPECTED_CHANNEL_ID}" ]] || {
    echo "E_LEZ_FINGERPRINT_CHANNEL_MISMATCH: expected=${EXPECTED_CHANNEL_ID} actual=${channel_id}" >&2
    exit 1
  }
fi

last_block_id="$(rpc_call getLastBlockId | jq -r '.')"
[[ "${last_block_id}" =~ ^[0-9]+$ ]] || {
  echo "E_LEZ_FINGERPRINT_LAST_BLOCK_ID: ${last_block_id}" >&2
  exit 1
}

program_ids="$(rpc_call getProgramIds | jq -cS '.')"
expected_program_ids="$(jq -cS '.' <<<"${EXPECTED_PROGRAM_IDS}")"
builtins_match=false
if [[ "${program_ids}" == "${expected_program_ids}" ]]; then
  builtins_match=true
fi

observed_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
jq -n \
  --arg rpc_url "${RPC_URL}" \
  --arg observed_at "${observed_at}" \
  --arg channel_id "${channel_id}" \
  --argjson last_block_id "${last_block_id}" \
  --argjson program_ids "${program_ids}" \
  --arg compatible_release "v0.2.4" \
  --arg compatible_commit "${LEZ_V024_COMMIT}" \
  --argjson builtins_match "${builtins_match}" \
  '{
    rpc_url: $rpc_url,
    observed_at: $observed_at,
    healthy: true,
    channel_id: $channel_id,
    last_block_id: $last_block_id,
    program_ids: $program_ids,
    compatibility: {
      builtins_match: $builtins_match,
      latest_matching_release: $compatible_release,
      pinned_commit: $compatible_commit,
      exact_server_version_confirmed: false
    }
  }'

if [[ "${builtins_match}" != "true" && "${ENFORCE}" == "1" ]]; then
  echo "E_LEZ_FINGERPRINT_MISMATCH: built-ins do not match pinned LEZ v0.2.4" >&2
  exit 1
fi
