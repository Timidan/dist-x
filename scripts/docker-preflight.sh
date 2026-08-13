#!/usr/bin/env bash
set -euo pipefail

GROTH16_IMAGE="risczero/risc0-groth16-prover:v2025-04-03.1"
GROTH16_DIGEST="sha256:a4f80ce2e0b8e2bb7637a93c37136a6776ac00ec843a3fdf1c67b1d5ffea64ee"
GROTH16_REFERENCE="risczero/risc0-groth16-prover@${GROTH16_DIGEST}"

if ! command -v docker >/dev/null 2>&1; then
  echo "E_DISTRIBUTIONX_DOCKER_MISSING: Docker is required for the Risc0 Groth16 receipt" >&2
  exit 2
fi

docker_context="$(docker context show 2>/dev/null || printf 'unknown')"
if ! docker info >/dev/null 2>&1; then
  echo "E_DISTRIBUTIONX_DOCKER_UNAVAILABLE: context=${docker_context}" >&2
  echo "Start that Docker daemon or select a working daemon before the real-proof run." >&2
  exit 2
fi

if ! docker image inspect "${GROTH16_REFERENCE}" >/dev/null 2>&1; then
  echo "RISC0_DOCKER_PULL image=${GROTH16_REFERENCE}"
  if ! docker pull "${GROTH16_REFERENCE}"; then
    echo "E_DISTRIBUTIONX_GROTH16_IMAGE_UNAVAILABLE: ${GROTH16_REFERENCE}" >&2
    exit 2
  fi
fi

# Risc0 3.0.x invokes this tag internally. Bind it to the verified digest so a
# mutable registry tag cannot alter the prover used by the lifecycle.
if ! docker tag "${GROTH16_REFERENCE}" "${GROTH16_IMAGE}"; then
  echo "E_DISTRIBUTIONX_GROTH16_TAG_FAILED: ${GROTH16_REFERENCE}" >&2
  exit 2
fi

if ! docker run --rm --network none --entrypoint /bin/true "${GROTH16_IMAGE}" >/dev/null 2>&1; then
  echo "E_DISTRIBUTIONX_GROTH16_CONTAINER_UNAVAILABLE: image=${GROTH16_IMAGE} context=${docker_context}" >&2
  echo "The pinned prover image must start with Docker's null network before proof generation." >&2
  exit 2
fi

echo "RISC0_DOCKER_READY image=${GROTH16_IMAGE} digest=${GROTH16_DIGEST} context=${docker_context}"
