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

reset_root="${TEST_DIR}/reset-root"
mkdir -p "${reset_root}/scripts" "${reset_root}/fixtures/reviewer-fast-path"
cp "${ROOT}/scripts/start-basecamp.sh" "${reset_root}/scripts/start-basecamp.sh"
for helper in standalone-sequencer.sh deploy.sh; do
  cat >"${reset_root}/scripts/${helper}" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod 0755 "${reset_root}/scripts/${helper}"
done
cat >"${reset_root}/scripts/wallet-bootstrap.sh" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >"${TEST_DIR}/wallet-bootstrap-args"
printf '%s\\n' 'Public/CbgR6tj5kWx5oziiFptM7jMvrQeYY3Mzaao6ciuhSr2r'
EOF
chmod 0755 "${reset_root}/scripts/wallet-bootstrap.sh"

PATH="/usr/bin:/bin" \
  LEZ_RPC_URL=http://127.0.0.1:3040 \
  DISTRIBUTIONX_ENV_FILE=/dev/null \
  DISTRIBUTIONX_STATE_DIR="${TEST_DIR}/reset-state" \
  DISTRIBUTIONX_LGX_DIR="${TEST_DIR}/missing-lgx" \
  DISTRIBUTIONX_NIX_STORE_ROOT="${TEST_DIR}" \
  bash "${reset_root}/scripts/start-basecamp.sh" \
    --reset-localnet \
    --no-package \
    --no-install \
    --no-launch >/dev/null

grep -Fxq -- '--clean' "${TEST_DIR}/wallet-bootstrap-args" || {
  echo "basecamp-launcher-test: reset-localnet did not clean the fixture wallet" >&2
  exit 1
}

install_dir="${TEST_DIR}/installed"
lgx_dir="${TEST_DIR}/lgx"
package_dir="${TEST_DIR}/package"
mkdir -p "${lgx_dir}" "${package_dir}"
touch "${lgx_dir}/distributionx-client.lgx"
printf '%s\n' '{"name":"distributionx","type":"ui_qml","view":"src/qml/Main.qml"}' \
  >"${package_dir}/manifest.json"
tar -czf "${lgx_dir}/DistributionX-ui.lgx" -C "${package_dir}" manifest.json

cat >"${TEST_DIR}/lgpm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ui_dir=""
file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ui-plugins-dir) ui_dir="$2"; shift 2 ;;
    --modules-dir) shift 2 ;;
    --allow-unsigned|install) shift ;;
    --file) file="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ "${file}" == *DistributionX-ui.lgx ]]; then
  mkdir -p "${ui_dir}/distributionx/src/qml"
  printf '%s\n' '{"name":"distributionx","type":"ui_qml"}' \
    >"${ui_dir}/distributionx/manifest.json"
  touch "${ui_dir}/distributionx/src/qml/Main.qml"
fi
EOF
chmod 0755 "${TEST_DIR}/lgpm"

PATH="/usr/bin:/bin" \
  LGPM_BIN="${TEST_DIR}/lgpm" \
  LEZ_RPC_URL=https://testnet.lez.logos.co \
  DISTRIBUTIONX_ENV_FILE=/dev/null \
  DISTRIBUTIONX_LGX_DIR="${lgx_dir}" \
  DISTRIBUTIONX_BASECAMP_USER_DIR="${install_dir}" \
  DISTRIBUTIONX_NIX_STORE_ROOT="${TEST_DIR}" \
  bash "${reset_root}/scripts/start-basecamp.sh" \
    --no-package \
    --clean-user-dir \
    --no-launch >/dev/null

[[ "$(jq -r '.view // empty' "${install_dir}/plugins/distributionx/manifest.json")" == \
  'src/qml/Main.qml' ]] || {
  echo "basecamp-launcher-test: installer-stripped UI view was not restored" >&2
  exit 1
}

echo "basecamp-launcher-test: PASS"
