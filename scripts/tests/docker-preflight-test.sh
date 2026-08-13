#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_BIN="${ROOT}/scripts/tests/fixtures"
PREFLIGHT="${ROOT}/scripts/docker-preflight.sh"
IMAGE="risczero/risc0-groth16-prover:v2025-04-03.1"
DIGEST="sha256:a4f80ce2e0b8e2bb7637a93c37136a6776ac00ec843a3fdf1c67b1d5ffea64ee"
REFERENCE="risczero/risc0-groth16-prover@${DIGEST}"

fail() {
  printf 'docker-preflight-test: %s\n' "$*" >&2
  exit 1
}

set +e
unavailable_output="$(
  PATH="${FIXTURE_BIN}:${PATH}" \
    DISTRIBUTIONX_TEST_DOCKER_MODE=unavailable \
    bash "${PREFLIGHT}" 2>&1
)"
unavailable_status=$?
set -e
[[ "${unavailable_status}" == "2" ]] \
  || fail "unavailable daemon returned ${unavailable_status}, expected 2"
[[ "${unavailable_output}" == *"E_DISTRIBUTIONX_DOCKER_UNAVAILABLE"* ]] \
  || fail "unavailable daemon did not return the stable error code"
[[ "${unavailable_output}" == *"test-unavailable"* ]] \
  || fail "unavailable daemon error omitted the selected context"

missing_output="$(
  PATH="${FIXTURE_BIN}:${PATH}" \
    DISTRIBUTIONX_TEST_DOCKER_MODE=missing-image \
    bash "${PREFLIGHT}" 2>&1
)"
[[ "${missing_output}" == *"FAKE_DOCKER_PULL_OK ${REFERENCE}"* ]] \
  || fail "missing Groth16 digest was not pulled during preflight"
[[ "${missing_output}" == *"RISC0_DOCKER_READY image=${IMAGE} digest=${DIGEST}"* ]] \
  || fail "missing-image path did not become ready"

ready_log="$(mktemp)"
trap 'rm -f "${ready_log}"' EXIT
ready_output="$(
  PATH="${FIXTURE_BIN}:${PATH}" \
    DISTRIBUTIONX_TEST_DOCKER_MODE=ready \
    DISTRIBUTIONX_TEST_DOCKER_LOG="${ready_log}" \
    bash "${PREFLIGHT}" 2>&1
)"
[[ "${ready_output}" == *"RISC0_DOCKER_READY image=${IMAGE} digest=${DIGEST}"* ]] \
  || fail "ready daemon did not report the pinned Groth16 image"
grep -Fxq "tag ${REFERENCE} ${IMAGE}" "${ready_log}" \
  || fail "preflight did not bind the hardcoded Risc0 tag to the expected digest"
grep -Fxq "run --rm --network none --entrypoint /bin/true ${IMAGE}" "${ready_log}" \
  || fail "preflight did not prove that the pinned image can start without bridge networking"

echo "docker-preflight-test: PASS"
