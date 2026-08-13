#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAIN_QML="${ROOT}/basecamp-app/src/qml/Main.qml"
WIZARD_QML="${ROOT}/basecamp-app/src/qml/screens/DistributorWizard.qml"
LOAD_SMOKE="${ROOT}/scripts/lgx-load-smoke.sh"
LOAD_PROBE="${ROOT}/scripts/lgx-load-probe.mjs"
README="${ROOT}/README.md"
VIDEO_SCRIPT="${ROOT}/docs/demo-video-script.md"
RC5_HANDOFF="${ROOT}/docs/RC5_PPE_HANDOFF.md"

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
grep -Fq 'value: tokenSourceAccount !== "" ? "Configured" : "Optional", ok: true' "${MAIN_QML}" \
  || fail "readiness still blocks when custom-token settlement is absent"

if grep -Fq 'if (tokenSourceAccount === "") missing.push("DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT")' "${MAIN_QML}"; then
  fail "testnet configuration still requires a custom-token source"
fi
if grep -Fq 'tokenId === "" || tokenSourceAccount === "" || recoveryAddress === ""' "${MAIN_QML}"; then
  fail "distribution initialization still requires a custom-token source"
fi
if grep -Fq 'if (appRoot.tokenSourceAccount === "") return "Token source account is required before Initialize."' "${WIZARD_QML}"; then
  fail "the distributor wizard still blocks without custom-token settlement"
fi
grep -Fq 'label: "Custom-token source account (optional)"' "${WIZARD_QML}" \
  || fail "the distributor wizard does not present custom-token settlement as optional"
if grep -Fq '&& appRoot.tokenSourceAccount !== ""' "${WIZARD_QML}"; then
  fail "the Initialize button still requires a custom-token source"
fi
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

grep -Fq '`claim_ppe`, not `claim_private`, is shown and named' "${VIDEO_SCRIPT}" \
  || fail "the video checklist does not require the shipping PPE path"
grep -Fq 'local claimant' "${VIDEO_SCRIPT}" \
  || fail "the video checklist overstates the demonstrated duplicate rejection"
if grep -Eq 'bash scripts/e2e\.sh (basecamp|localnet)' "${VIDEO_SCRIPT}"; then
  fail "the video checklist still uses removed e2e entry points"
fi

grep -Fq 'Historical only. Do not follow this file as an operator runbook.' "${RC5_HANDOFF}" \
  || fail "the rc5 handoff is not prominently archived"
if grep -Fq 'Testnet runs **LEZ v0.2.0-rc5**' "${RC5_HANDOFF}"; then
  fail "the rc5 handoff still describes the historical network as current"
fi

echo "basecamp-release-gates-test: PASS"
