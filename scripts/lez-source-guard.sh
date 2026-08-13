#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEZ_REPO="${1:-${DISTRIBUTIONX_LEZ_REPO:-${ROOT}/.scaffold/cache/repos/lez/v0.2.4}}"
EXPECTED_COMMIT="47eba256479f6f785acbd138834340703cd03401"
if [[ "${DISTRIBUTIONX_LEZ_SOURCE_GUARD_TESTING:-0}" == "1" ]]; then
  EXPECTED_COMMIT="${DISTRIBUTIONX_EXPECTED_LEZ_COMMIT:?test expected commit required}"
fi

die() {
  printf 'E_DISTRIBUTIONX_LEZ_SOURCE: %s\n' "$*" >&2
  exit 1
}

[[ -d "${LEZ_REPO}/.git" ]] \
  || die "checkout not found at ${LEZ_REPO}"

actual="$(git -C "${LEZ_REPO}" rev-parse HEAD 2>/dev/null)" \
  || die "cannot resolve HEAD at ${LEZ_REPO}"
[[ "${actual}" == "${EXPECTED_COMMIT}" ]] \
  || die "checkout is ${actual}; expected ${EXPECTED_COMMIT}"

git -C "${LEZ_REPO}" diff --quiet --ignore-submodules HEAD -- \
  || die "checkout has tracked or staged source changes"

untracked="$(git -C "${LEZ_REPO}" ls-files --others --exclude-standard)"
[[ -z "${untracked}" ]] \
  || die "checkout has untracked source; use a clean exact checkout"

printf '%s\n' "${actual}"
