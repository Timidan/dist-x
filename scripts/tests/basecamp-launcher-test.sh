#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "${TEST_DIR}"' EXIT

bundle="${TEST_DIR}/a-logos-basecamp-bundle-0.0.0/bin/LogosBasecamp"
unwrapped="${TEST_DIR}/z-logos-basecamp-0.0.0/bin/LogosBasecamp"
mkdir -p "$(dirname "${bundle}")" "$(dirname "${unwrapped}")"
touch "${bundle}" "${unwrapped}"
chmod 0755 "${bundle}" "${unwrapped}"

output="$({
  PATH="/usr/bin:/bin" \
    DISTRIBUTIONX_ENV_FILE=/dev/null \
    DISTRIBUTIONX_LGX_DIR="${TEST_DIR}/missing-lgx" \
    DISTRIBUTIONX_NIX_STORE_ROOT="${TEST_DIR}" \
    bash "${ROOT}/scripts/start-basecamp.sh" \
      --no-package \
      --no-install \
      --no-launch
} 2>&1)"

grep -Fq "Command: ${bundle}" <<<"${output}" || {
  printf '%s\n' "${output}" >&2
  echo "basecamp-launcher-test: bundled Basecamp was not preferred" >&2
  exit 1
}

echo "basecamp-launcher-test: PASS"
