#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:-localnet}"
if [[ $# -gt 0 ]]; then
  shift
fi

exec bash "${ROOT}/scripts/e2e.sh" "${mode}" "$@"
