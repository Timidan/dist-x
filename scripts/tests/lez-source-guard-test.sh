#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "${TEST_DIR}"' EXIT

repo="${TEST_DIR}/lez"
git init -q "${repo}"
git -C "${repo}" config user.name test
git -C "${repo}" config user.email test@example.invalid
printf '%s\n' pinned >"${repo}/source.txt"
git -C "${repo}" add source.txt
git -C "${repo}" commit -qm pinned
commit="$(git -C "${repo}" rev-parse HEAD)"

output="$(DISTRIBUTIONX_LEZ_SOURCE_GUARD_TESTING=1 \
  DISTRIBUTIONX_EXPECTED_LEZ_COMMIT="${commit}" \
  bash "${ROOT}/scripts/lez-source-guard.sh" "${repo}")"
[[ "${output}" == "${commit}" ]]

printf '%s\n' dirty >>"${repo}/source.txt"
if DISTRIBUTIONX_LEZ_SOURCE_GUARD_TESTING=1 \
  DISTRIBUTIONX_EXPECTED_LEZ_COMMIT="${commit}" \
  bash "${ROOT}/scripts/lez-source-guard.sh" "${repo}" >/dev/null 2>&1; then
  echo "lez-source-guard-test: accepted tracked source changes" >&2
  exit 1
fi
git -C "${repo}" restore source.txt

printf '%s\n' untracked >"${repo}/untracked.txt"
if DISTRIBUTIONX_LEZ_SOURCE_GUARD_TESTING=1 \
  DISTRIBUTIONX_EXPECTED_LEZ_COMMIT="${commit}" \
  bash "${ROOT}/scripts/lez-source-guard.sh" "${repo}" >/dev/null 2>&1; then
  echo "lez-source-guard-test: accepted untracked source" >&2
  exit 1
fi
rm "${repo}/untracked.txt"

if DISTRIBUTIONX_LEZ_SOURCE_GUARD_TESTING=1 \
  DISTRIBUTIONX_EXPECTED_LEZ_COMMIT="0000000000000000000000000000000000000000" \
  bash "${ROOT}/scripts/lez-source-guard.sh" "${repo}" >/dev/null 2>&1; then
  echo "lez-source-guard-test: accepted the wrong commit" >&2
  exit 1
fi

echo "lez-source-guard-test: PASS"
