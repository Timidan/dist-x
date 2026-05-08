#!/usr/bin/env bash
set -euo pipefail

out_dir="${1:-/tmp/distributionx-modules-v2}"
client_input="${2:-${DISTRIBUTIONX_CLIENT_MODULE_LIB:-}}"

find_standalone_app() {
  if [[ -n "${LOGOS_STANDALONE_APP:-}" ]]; then
    printf '%s\n' "${LOGOS_STANDALONE_APP}"
    return
  fi
  if command -v logos-standalone-app >/dev/null 2>&1; then
    command -v logos-standalone-app
    return
  fi
  find /nix/store -maxdepth 4 -path '*/bin/logos-standalone-app' 2>/dev/null | sort | tail -n 1
}

standalone_app="$(find_standalone_app)"
if [[ -z "${standalone_app}" || ! -x "${standalone_app}" ]]; then
  echo "logos-standalone-app not found. Set LOGOS_STANDALONE_APP." >&2
  exit 2
fi

if [[ -z "${client_input}" ]]; then
  if [[ -f "distributionx_client_module/result/lib/distributionx_client_plugin.so" ]]; then
    client_input="distributionx_client_module/result/lib"
  elif [[ -f "/tmp/distributionx-modules-v2/distributionx_client_plugin.so" ]]; then
    client_input="/tmp/distributionx-modules-v2"
  else
    echo "usage: $0 [modules-dir] [client-lib-dir-or-plugin-so]" >&2
    echo "set DISTRIBUTIONX_CLIENT_MODULE_LIB when the client plugin is not in a default location" >&2
    exit 2
  fi
fi

if [[ -d "${client_input}" ]]; then
  client_lib_dir="${client_input}"
  client_plugin="${client_lib_dir}/distributionx_client_plugin.so"
else
  client_plugin="${client_input}"
  client_lib_dir="$(cd "$(dirname "${client_plugin}")" && pwd)"
fi

if [[ ! -f "${client_plugin}" ]]; then
  echo "distributionx_client_plugin.so not found: ${client_plugin}" >&2
  exit 2
fi

is_distributionx_cli() {
  local candidate="$1"
  [[ -n "${candidate}" && -x "${candidate}" ]] || return 1
  "${candidate}" --help >/dev/null 2>&1
}

find_distributionx_cli() {
  local candidates=(
    "${DISTRIBUTIONX_CLI:-}"
    "target/release/distributionx-cli"
    "target/debug/distributionx-cli"
    "${client_lib_dir}/distributionx-cli"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if is_distributionx_cli "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

cli_source="$(find_distributionx_cli)" || {
  echo "distributionx-cli binary not found." >&2
  echo "Build it first with: cargo build -p distributionx-cli" >&2
  echo "Or set DISTRIBUTIONX_CLI=/absolute/path/to/distributionx-cli." >&2
  exit 2
}

standalone_root="$(cd "$(dirname "${standalone_app}")/.." && pwd)"
capability_dir="${standalone_root}/modules/capability_module"
if [[ ! -d "${capability_dir}" ]]; then
  echo "capability_module bundle not found under standalone app: ${capability_dir}" >&2
  exit 2
fi

mkdir -p "${out_dir}/distributionx_client" "${out_dir}/capability_module"
install -m 755 "${client_plugin}" "${out_dir}/distributionx_client/distributionx_client_plugin.so"
install -m 755 "${cli_source}" "${out_dir}/distributionx_client/distributionx-cli"
install -m 755 "${capability_dir}/capability_module_plugin.so" "${out_dir}/capability_module/capability_module_plugin.so"
install -m 644 "${capability_dir}/manifest.json" "${out_dir}/capability_module/manifest.json"

rm -f "${out_dir}/distributionx_client/manifest.json"
cat > "${out_dir}/distributionx_client/manifest.json" <<'JSON'
{
  "manifestVersion": "0.2.0",
  "name": "distributionx_client",
  "version": "0.1.0",
  "description": "Logos module wrapper for DistributionX private distribution client operations",
  "author": "DistributionX",
  "type": "core",
  "category": "tools",
  "dependencies": [],
  "main": "distributionx_client_plugin.so"
}
JSON

echo "DISTRIBUTIONX_MODULES_DIR=${out_dir}"
