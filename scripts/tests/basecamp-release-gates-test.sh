#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAIN_QML="${ROOT}/basecamp-app/src/qml/Main.qml"
WIZARD_QML="${ROOT}/basecamp-app/src/qml/screens/DistributorWizard.qml"
LOAD_SMOKE="${ROOT}/scripts/lgx-load-smoke.sh"
LOAD_PROBE="${ROOT}/scripts/lgx-load-probe.mjs"
README="${ROOT}/README.md"

fail() {
  printf 'basecamp-release-gates-test: %s\n' "$*" >&2
  exit 1
}

grep -Fq 'property bool clientModuleReady: false' "${MAIN_QML}" \
  || fail "Main.qml has no explicit client API readiness state"
grep -Fq 'clientModuleReady = true' "${MAIN_QML}" \
  || fail "a successful registry API response does not mark the client ready"
grep -Fq 'label: "Custom-token source"' "${MAIN_QML}" \
  || fail "readiness does not label custom-token settlement separately"
grep -Fq 'var tokenSourceRequired = payoutMode === "custom"' "${MAIN_QML}" \
  || fail "readiness does not distinguish native and custom-token payout modes"
grep -Fq 'ok: !tokenSourceRequired || tokenSourceAccount !== ""' "${MAIN_QML}" \
  || fail "readiness does not require a source only for custom-token mode"

if grep -Fq 'if (tokenSourceAccount === "") missing.push("DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT")' "${MAIN_QML}"; then
  fail "testnet configuration still requires a custom-token source"
fi
if grep -Fq 'tokenId === "" || tokenSourceAccount === "" || recoveryAddress === ""' "${MAIN_QML}"; then
  fail "distribution initialization still requires a custom-token source"
fi
if grep -Fq 'if (appRoot.tokenSourceAccount === "") return "Token source account is required before Initialize."' "${WIZARD_QML}"; then
  fail "the distributor wizard still blocks without custom-token settlement"
fi
grep -Fq 'visible: appRoot && appRoot.payoutMode === "custom"' "${WIZARD_QML}" \
  || fail "the distributor wizard exposes custom-token controls in native mode"
grep -Fq '&& (appRoot.payoutMode !== "custom" || appRoot.tokenSourceAccount !== "")' "${WIZARD_QML}" \
  || fail "the Initialize button does not enforce the selected payout mode"
grep -Fq 'if (!appRoot.customTokenSettlementConfigured()) return true' "${WIZARD_QML}" \
  || fail "native distribution-pool funding still requires a custom-token balance"
grep -Fq 'return "Native distribution pool funding"' "${WIZARD_QML}" \
  || fail "the funding card still describes native prefunding as a token-source balance"
grep -Fq '!appRoot.customTokenSettlementConfigured()' "${WIZARD_QML}" \
  || fail "the funding error state does not distinguish native-only mode"
grep -Fq 'property string lastTokenSettlementTxId: ""' "${MAIN_QML}" \
  || fail "Basecamp cannot distinguish a confirmed custom-token settlement"
grep -Fq 'if (!customTokenSettlementConfigured()) return true' "${MAIN_QML}" \
  || fail "the native-only path still queries the custom-token program"
grep -Fq 'return "Native payout confirmed"' "${MAIN_QML}" \
  || fail "the native-only success state is not labelled honestly"
if grep -Fq 'sampleStatus = "Tokens delivered"' "${MAIN_QML}"; then
  fail "sample completion still reports unconfirmed custom tokens"
fi

[[ -s "${LOAD_PROBE}" ]] \
  || fail "the installed-LGX QML/API probe is missing"
grep -Fq 'clientModuleReady' "${LOAD_PROBE}" \
  || fail "the installed-LGX probe does not require a client API response"
grep -Fq 'lgx-load-probe.mjs' "${LOAD_SMOKE}" \
  || fail "the LGX smoke does not run the QML/API probe"
grep -Fq 'E_DISTRIBUTIONX_LGX_INSPECTOR_PORT_IN_USE' "${LOAD_SMOKE}" \
  || fail "the LGX smoke can attach its readiness probe to an unrelated app"
grep -Fq 'CORE_CLI="${SMOKE_DIR}/modules/distributionx_client/distributionx-cli"' "${LOAD_SMOKE}" \
  || fail "the LGX smoke does not require the packaged CLI"
grep -Fq 'DISTRIBUTIONX_CLI="${CORE_CLI}"' "${LOAD_SMOKE}" \
  || fail "the LGX smoke can fall back to a development CLI"
grep -Fq 'cd "${SMOKE_DIR}"' "${LOAD_SMOKE}" \
  || fail "the LGX smoke still launches from the repository"

grep -Fq 'bash scripts/testnet-evidence.sh smoke "${quote_sha}"' "${README}" \
  || fail "the operator handoff omits the separately approved smoke phase"
grep -Fq 'bash scripts/testnet-evidence.sh finish "${quote_sha}"' "${README}" \
  || fail "the operator handoff omits the separately approved finish phase"
grep -Fq 'unset DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT' "${README}" \
  || fail "the operator handoff does not clear inherited custom-token state"
grep -Fq 'The publishable output is only' "${README}" \
  || fail "the operator handoff does not isolate witness-free public evidence"

echo "basecamp-release-gates-test: PASS"
