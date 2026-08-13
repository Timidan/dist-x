#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_DOCKER="${ROOT}/scripts/tests/fixtures/docker"
WRAPPER="${ROOT}/scripts/risc0-docker-bin/docker"
TEST_DIR="$(mktemp -d)"
IMAGE="risczero/risc0-groth16-prover:v2025-04-03.1"
trap 'rm -rf "${TEST_DIR}"' EXIT

fail() {
  printf 'docker-wrapper-test: %s\n' "$*" >&2
  exit 1
}

DISTRIBUTIONX_REAL_DOCKER="${FIXTURE_DOCKER}" \
  DISTRIBUTIONX_TEST_DOCKER_LOG="${TEST_DIR}/run.log" \
  bash "${WRAPPER}" run --rm -v /tmp/input:/mnt "${IMAGE}"

[[ "$(cat "${TEST_DIR}/run.log")" == \
  "run --network none --rm -v /tmp/input:/mnt ${IMAGE}" ]] \
  || fail "wrapper did not inject --network none immediately after docker run"

DISTRIBUTIONX_REAL_DOCKER="${FIXTURE_DOCKER}" \
  DISTRIBUTIONX_TEST_DOCKER_LOG="${TEST_DIR}/other-run.log" \
  bash "${WRAPPER}" run --rm alpine:3.21 true

[[ "$(cat "${TEST_DIR}/other-run.log")" == "run --rm alpine:3.21 true" ]] \
  || fail "wrapper changed an unrelated Docker run"

DISTRIBUTIONX_REAL_DOCKER="${FIXTURE_DOCKER}" \
  DISTRIBUTIONX_TEST_DOCKER_LOG="${TEST_DIR}/version.log" \
  bash "${WRAPPER}" --version >/dev/null

[[ "$(cat "${TEST_DIR}/version.log")" == "--version" ]] \
  || fail "wrapper changed a non-run Docker command"

echo "docker-wrapper-test: PASS"
