import QtQuick
import QtQuick.Controls
import "components"

Item {
    id: root
    width: 1120
    height: 760
    property string screen: "landing"
    property string sampleStatus: "Ready to claim"
    property string sampleDetail: ""
    property string sampleError: ""
    property bool sampleRunning: false
    property int sampleStepIndex: 0
    property var sampleSteps: []
    property string samplePendingJobId: ""
    property string samplePendingMarker: ""
    property string samplePendingOperation: ""
    property string duplicateClaimJobId: ""
    property string duplicateClaimStatus: ""
    property bool duplicateClaimRunning: false
    property bool autoQuitAfterSample: false
    property string destinationMode: "external-wallet"
    property string distributionStateDir: "target/distributionx-testnet"
    property string airdropName: "demo-airdrop"
    property string eligibilityCsvPath: distributionStateDir + "/eligible.csv"
    property string destinationPacket: distributionStateDir + "/shielded_destination.json"
    property string destinationCommitment: ""
    readonly property string claimantBalanceAccount: destinationCommitment !== "" ? "Public/" + destinationCommitment : ""
    property string claimLink: ""
    property string claimLinkError: ""
    property string claimBundleOverride: ""
    property string recoveryGateStatus: "attested"
    property string backupAttestedAt: ""
    property string testnetRpc: ""
    readonly property string localnetRpcSuggestion: "http://127.0.0.1:3040"
    property string distributorAccount: ""
    property string configuredDistributorAccount: ""
    property string payoutMode: "native"
    property string tokenId: ""
    property string tokenSourceAccount: ""
    property string recoveryAddress: ""
    property string fundAmount: "3000"
    property string expiryUnix: "1893456000"
    property string relayerUrl: "localnet"
    property string serializedLezTxPath: distributionStateDir + "/claim.tx"
    property bool initSubmitCommandConfigured: false
    property bool fundSubmitCommandConfigured: false
    property bool claimSubmitCommandConfigured: false
    property string distributorStatus: "Ready"
    property string distributorError: ""
    property string distributorTokenBalance: ""
    property string distributorTokenBalanceError: ""
    property string claimantTokenBalance: ""
    property string claimantTokenBalanceError: ""
    property string claimantTokenBalanceAccount: ""
    property string claimantTokenBalanceTokenId: ""
    property string claimantTokenBalanceAirdrop: ""
    property string claimantTokenBalanceClaimKey: ""
    property string claimantTokenBalanceNullifier: ""
    property int claimPageRefreshAttempts: 0
    property var airdrops: []
    property string selectedAirdropId: ""
    property string registryError: ""
    property bool clientModuleReady: false
    property int registryRefreshAttempts: 0
    property bool devUiEnabled: false
    property bool debugUiEnabled: false
    property string activeOperation: ""
    property string actionJobId: ""
    property string actionJobKind: ""
    property string actionJobMarker: ""
    property string actionJobLabel: ""
    readonly property bool actionRunning: actionJobId !== ""
    property real proofStartedAtMs: 0
    property int proofElapsedSeconds: 0
    property int lastProofDurationSeconds: 0
    property string lastAirdropId: ""
    property string lastInitTxId: ""
    property string lastBundlePath: ""
    property int lastEligibleCount: 0
    property string lastFundedAmount: ""
    property string lastFundTxId: ""
    property int lastTotalFunded: 0
    property int lastTotalClaimed: 0
    property string lastClaimTxId: ""
    property string lastTokenSettlementTxId: ""
    property string lastClaimAmount: ""
    property string lastProofPath: ""
    property string claimEligibilityStatus: "unchecked"
    property string claimEligibilityError: ""
    property string claimEligibilityAmount: ""
    property int claimEligibilityBucket: -1
    property string claimEligibilityNullifier: ""
    readonly property bool canClaim: destinationPacket !== "" && (destinationMode === "external-wallet" || recoveryGateStatus === "attested")
    readonly property bool claimEligibilityOk: claimEligibilityStatus === "eligible"
    readonly property bool proofRunning: proofStartedAtMs > 0

    onScreenChanged: if (screen === "claim") {
        scheduleClaimPageRefresh()
    }
    onDestinationPacketChanged: {
        resetClaimEligibility()
        resetClaimantBalance()
        if (screen === "claim") scheduleClaimPageRefresh()
    }
    onDestinationCommitmentChanged: {
        resetClaimantBalance()
        if (screen === "claim") scheduleClaimPageRefresh()
    }
    onSelectedAirdropIdChanged: {
        resetClaimEligibility()
        resetClaimantBalance()
    }
    onDistributionStateDirChanged: {
        resetClaimEligibility()
        resetClaimantBalance()
    }
    onTestnetRpcChanged: {
        Qt.callLater(queryDistributorBalance)
        Qt.callLater(queryClaimantBalance)
    }
    onDistributorAccountChanged: Qt.callLater(queryDistributorBalance)
    onTokenIdChanged: {
        resetClaimantBalance()
        Qt.callLater(queryDistributorBalance)
        Qt.callLater(queryClaimantBalance)
    }
    onTokenSourceAccountChanged: Qt.callLater(queryDistributorBalance)

    // Theme: Ledger Paper direction (warm cream, deep-rose seal, editorial serif)
    readonly property QtObject theme: QtObject {
        readonly property color bg:           "#F4EFE6"
        readonly property color surface:      "#FBF8F1"
        readonly property color surfaceSubtle:"#EFE9DD"
        readonly property color line:         Qt.rgba(28/255, 24/255, 20/255, 0.10)
        readonly property color lineStrong:   Qt.rgba(28/255, 24/255, 20/255, 0.18)
        readonly property color fg:           "#1B1612"
        readonly property color fg2:          "#5A5048"
        readonly property color fg3:          "#8E8579"
        readonly property color accent:       "#B0413E"
        readonly property color accentSoft:   Qt.rgba(176/255, 65/255, 62/255, 0.10)
        readonly property color accentInk:    "#FBF8F1"
        readonly property color danger:       "#9F1239"
        readonly property color dangerSoft:   Qt.rgba(159/255, 18/255, 57/255, 0.08)
        readonly property color success:      "#5C6B2F"
        readonly property int rSm: 4
        readonly property int rMd: 4
        readonly property int rLg: 6
        readonly property int rXl: 8
        readonly property int s1: 4
        readonly property int s2: 8
        readonly property int s3: 14
        readonly property int s4: 22
        readonly property int s5: 28
        readonly property int s6: 56
        readonly property string fontDisplay: "serif"
        readonly property string fontBody:    "sans-serif"
        readonly property string fontMono:    "monospace"
        readonly property int fpDisplayHero:  42
        readonly property int fpDisplayLg:    30
        readonly property int fpDisplayMd:    24
        readonly property int fpBody:         13
        readonly property int fpLabel:        11
        readonly property int durFast: 120
        readonly property int durBase: 220
        readonly property int durSlow: 420
    }

    function hasBridge() {
        return typeof logos !== "undefined" && logos && logos.callModule
    }

    function callClient(method, args) {
        if (!hasBridge()) {
            return "{\"status\":\"DISTRIBUTIONX_CLIENT_ERROR\",\"error\":\"DistributionX client module is not loaded\"}"
        }
        try {
            return logos.callModule("distributionx_client", method, args)
        } catch (e) {
            return "{\"status\":\"DISTRIBUTIONX_CLIENT_ERROR\",\"error\":\"" + String(e).replace(/"/g, "'") + "\"}"
        }
    }

    function callClientForStep(stepLabel, method, args) {
        activeOperation = stepLabel
        return callClient(method, args)
    }

    function isOperation(label) {
        return activeOperation === label
    }

    function responseHas(response, marker) {
        return String(response).indexOf(marker) !== -1
    }

    function parseClientJson(response) {
        var text = String(response).trim()
        try {
            var parsed = JSON.parse(text)
            if (typeof parsed === "string") {
                return parseClientJson(parsed)
            }
            return parsed
        } catch (e) {
        }
        var lines = text.split(/\n/)
        for (var i = lines.length - 1; i >= 0; i--) {
            var line = String(lines[i]).trim()
            if (line.charAt(0) !== "{") continue
            try {
                var parsedLine = JSON.parse(line)
                if (typeof parsedLine === "string") {
                    return parseClientJson(parsedLine)
                }
                return parsedLine
            } catch (e2) {
            }
        }
        return null
    }

    function argumentValue(prefix, fallback) {
        for (var i = 0; i < Qt.application.arguments.length; i++) {
            var arg = String(Qt.application.arguments[i])
            if (arg.indexOf(prefix) === 0) {
                return arg.substring(prefix.length)
            }
        }
        return fallback
    }

    function configureFromArguments() {
        distributionStateDir = argumentValue("distributionx-state-dir=", distributionStateDir)
        airdropName = argumentValue("distributionx-airdrop=", airdropName)
        testnetRpc = argumentValue("distributionx-rpc=", testnetRpc)
        configuredDistributorAccount = argumentValue("distributionx-distributor=", configuredDistributorAccount)
        distributorAccount = configuredDistributorAccount !== "" ? configuredDistributorAccount : distributorAccount
        tokenId = argumentValue("distributionx-token=", tokenId)
        tokenSourceAccount = argumentValue("distributionx-token-source=", tokenSourceAccount)
        payoutMode = tokenSourceAccount !== "" ? "custom" : "native"
        recoveryAddress = argumentValue("distributionx-recovery=", recoveryAddress)
        fundAmount = argumentValue("distributionx-fund-amount=", fundAmount)
        expiryUnix = argumentValue("distributionx-expiry-unix=", expiryUnix)
        relayerUrl = argumentValue("distributionx-relayer=", relayerUrl)
        eligibilityCsvPath = argumentValue("distributionx-eligibility-csv=", distributionStateDir + "/eligible.csv")
        destinationPacket = argumentValue("distributionx-destination-packet=", distributionStateDir + "/shielded_destination.json")
        serializedLezTxPath = argumentValue("distributionx-serialized-lez-tx=", distributionStateDir + "/claim.tx")
        var configuredClaimLink = argumentValue("distributionx-claim-link=", "")
        var configuredClaimBundle = argumentValue("distributionx-claim-bundle=", "")
        initSubmitCommandConfigured = argumentValue("distributionx-init-submit-command-configured=", initSubmitCommandConfigured ? "1" : "") === "1"
        fundSubmitCommandConfigured = argumentValue("distributionx-fund-submit-command-configured=", fundSubmitCommandConfigured ? "1" : "") === "1"
        claimSubmitCommandConfigured = argumentValue("distributionx-claim-submit-command-configured=", claimSubmitCommandConfigured ? "1" : "") === "1"
        devUiEnabled = argumentValue("distributionx-dev-ui=", devUiEnabled ? "1" : "0") === "1"
        debugUiEnabled = argumentValue("distributionx-debug-ui=", debugUiEnabled ? "1" : "0") === "1"
        if (configuredClaimLink !== "") applyClaimLink(configuredClaimLink)
        if (configuredClaimBundle !== "") setClaimBundlePath(configuredClaimBundle)
    }

    function networkModeLabel() {
        if (testnetRpc === "") return "RPC missing"
        if (isLocalRpc()) return "Localnet"
        return "Testnet"
    }

    function networkContextTitle() {
        if (testnetRpc === "") return "Network not configured"
        return isLocalRpc() ? "Local rehearsal" : "Public testnet"
    }

    function shortPubkey(value) {
        var t = String(value || "")
        if (t === "") return ""
        // strip "Public/" prefix for the visible label, then head…tail elide
        var bare = t.indexOf("Public/") === 0 ? t.substring(7) : t
        if (bare.length <= 14) return t
        return (t.indexOf("Public/") === 0 ? "Public/" : "") + bare.substring(0, 6) + "…" + bare.substring(bare.length - 4)
    }

    function readinessItems() {
        var items = []
        items.push({ label: "RPC", value: testnetRpc !== "" ? "Connected" : "Missing", ok: testnetRpc !== "" })
        items.push({ label: "Distributor signer", value: distributorAccount !== "" ? "Configured" : "Missing", ok: distributorAccount !== "" })
        items.push({ label: "Token id", value: tokenId !== "" ? "Configured" : "Missing", ok: tokenId !== "" })
        var tokenSourceRequired = payoutMode === "custom"
        items.push({ label: "Custom-token source", value: tokenSourceAccount !== "" ? "Configured" : (tokenSourceRequired ? "Missing" : "Not used"), ok: !tokenSourceRequired || tokenSourceAccount !== "" })
        items.push({ label: "Recovery account", value: recoveryAddress !== "" ? "Configured" : "Missing", ok: recoveryAddress !== "" })
        var relayerOk = relayerUrl !== "" && claimSubmitCommandConfigured
        var relayerValue = relayerUrl !== "" && claimSubmitCommandConfigured ? "Configured" : "Missing"
        items.push({ label: "Relayer / claim submit", value: relayerValue, ok: relayerOk })
        var submitOk = initSubmitCommandConfigured && fundSubmitCommandConfigured
        var submitValue = submitOk ? "Configured" : (!initSubmitCommandConfigured && !fundSubmitCommandConfigured ? "Missing" : (!initSubmitCommandConfigured ? "INIT missing" : "FUND missing"))
        items.push({ label: "Init/fund submit", value: submitValue, ok: submitOk })
        var registryOk = airdrops.length > 0
        var registryValue = airdrops.length > 0 ? (airdrops.length + " loaded") : (registryError !== "" ? "Unavailable" : "Empty")
        items.push({ label: "Registry", value: registryValue, ok: registryOk })
        return items
    }

    function readinessBlockingMessage() {
        var items = readinessItems()
        var missing = []
        for (var i = 0; i < items.length; i++) {
            if (!items[i].ok && items[i].label !== "Registry") missing.push(items[i].label)
        }
        if (missing.length === 0) return ""
        return "Missing: " + missing.join(", ")
    }

    readonly property bool readinessOk: readinessBlockingMessage() === ""

    function testnetConfigurationError() {
        var missing = []
        if (testnetRpc === "") missing.push("LEZ_RPC_URL")
        if (distributorAccount === "") missing.push("LEZ_DEPLOYER_WALLET")
        if (tokenId === "") missing.push("DISTRIBUTIONX_TOKEN_ID")
        if (recoveryAddress === "") missing.push("DISTRIBUTIONX_RECOVERY_ADDRESS")
        if (serializedLezTxPath === "") missing.push("DISTRIBUTIONX_SERIALIZED_LEZ_TX")
        if (!initSubmitCommandConfigured) missing.push("DISTRIBUTIONX_INIT_SUBMIT_COMMAND")
        if (!fundSubmitCommandConfigured) missing.push("DISTRIBUTIONX_FUND_SUBMIT_COMMAND")
        if (relayerUrl === "") missing.push("DISTRIBUTIONX_RELAYER_URL")
        if (!claimSubmitCommandConfigured) missing.push("DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND")
        if (missing.length === 0) return ""
        return "Configuration error: set " + missing.join(", ") + " before running the sample."
    }

    function isLocalRpc() {
        return testnetRpc.indexOf("http://127.0.0.1") === 0 || testnetRpc.indexOf("http://localhost") === 0
    }

    function refreshAirdrops() {
        registryError = ""
        clientModuleReady = false
        var response = callClient("listAirdrops", [])
        if (!responseHas(response, "AIRDROPS_OK")) {
            airdrops = []
            registryError = friendlyError(response)
            console.log("DISTRIBUTIONX_REGISTRY_EMPTY_OR_UNAVAILABLE", registryError)
            return false
        }
        var parsed = parseClientJson(response)
        if (!parsed || !parsed.airdrops) {
            airdrops = []
            registryError = "Invalid registry response"
            console.log("DISTRIBUTIONX_REGISTRY_PARSE_EMPTY", String(response))
            return false
        }
        clientModuleReady = true
        airdrops = parsed.airdrops
        if (airdrops.length > 0 && selectedAirdropId === "") {
            selectedAirdropId = airdrops[0].airdrop_id
        } else if (airdrops.length === 0) {
            selectedAirdropId = ""
        }
        if (screen === "claim") Qt.callLater(refreshClaimEligibility)
        return true
    }

    function refreshAirdropsUntilReady() {
        registryRefreshAttempts = 0
        if (!refreshAirdrops()) {
            registryRefreshTimer.restart()
        }
    }

    function selectedAirdrop() {
        for (var i = 0; i < airdrops.length; i++) {
            if (airdrops[i].airdrop_id === selectedAirdropId || airdrops[i].name === selectedAirdropId) {
                return airdrops[i]
            }
        }
        return airdrops.length > 0 ? airdrops[0] : null
    }

    function activeTokenId() {
        if (tokenId !== "") return tokenId
        var selected = selectedAirdrop()
        return selected && selected.token_id ? String(selected.token_id) : ""
    }

    function activeTokenSourceAccount() {
        if (tokenSourceAccount !== "") return tokenSourceAccount
        var selected = selectedAirdrop()
        return selected && selected.token_source_account ? String(selected.token_source_account) : ""
    }

    function customTokenSettlementConfigured() {
        return activeTokenSourceAccount() !== ""
    }

    function customTokenSettlementConfirmed() {
        return lastTokenSettlementTxId !== ""
    }

    function claimCompletionStatus() {
        if (customTokenSettlementConfirmed()) return "Custom-token settlement confirmed"
        if (customTokenSettlementConfigured() && lastClaimTxId === "") return "Claim settlement"
        return "Native payout confirmed"
    }

    function claimCompleted() {
        return sampleStatus === "Native payout confirmed"
            || sampleStatus === "Custom-token settlement confirmed"
    }

    function selectRegistryAirdrop(airdropId, name) {
        selectedAirdropId = airdropId
        airdropName = name
        claimBundleOverride = ""
        claimLink = ""
        claimLinkError = ""
        var selected = selectedAirdrop()
        if (selected && selected.token_id) tokenId = String(selected.token_id)
        tokenSourceAccount = selected && selected.token_source_account ? String(selected.token_source_account) : ""
        resetClaimEligibility()
        resetClaimantBalance()
    }

    function claimAirdropName() {
        var selected = selectedAirdrop()
        return selected && selected.name ? String(selected.name) : airdropName
    }

    function claimBundlePath() {
        if (claimBundleOverride !== "") return normalizeFilePath(claimBundleOverride)
        var selected = selectedAirdrop()
        return selected && selected.bundle_path ? String(selected.bundle_path) : distributionStateDir + "/bundle.json"
    }

    function setClaimBundlePath(path) {
        claimBundleOverride = normalizeFilePath(path)
        claimLinkError = ""
        resetClaimEligibility()
        resetClaimantBalance()
        if (screen === "claim") Qt.callLater(refreshClaimEligibility)
    }

    function shareClaimLink() {
        var bundle = lastBundlePath !== "" ? lastBundlePath : distributionStateDir + "/bundle.json"
        return "distributionx://claim?id=" + encodeURIComponent(airdropName) + "&bundle=" + encodeURIComponent(bundle)
    }

    function normalizeFilePath(path) {
        var value = String(path || "")
        if (value.indexOf("file://") === 0) return value.substring(7)
        return value
    }

    function claimLinkParam(query, key) {
        var parts = String(query || "").split("&")
        for (var i = 0; i < parts.length; i++) {
            var pair = parts[i].split("=")
            var decodedKey = pair[0] || ""
            try {
                decodedKey = decodeURIComponent(decodedKey)
            } catch (eKey) {
            }
            if (decodedKey === key) {
                try {
                    return decodeURIComponent((pair.slice(1).join("=") || "").replace(/\+/g, " "))
                } catch (e) {
                    return pair.slice(1).join("=") || ""
                }
            }
        }
        return ""
    }

    function applyClaimLink(value) {
        claimLink = String(value || "").trim()
        claimLinkError = ""
        if (claimLink === "") return false

        var query = ""
        var q = claimLink.indexOf("?")
        if (q !== -1) {
            query = claimLink.substring(q + 1)
        } else if (claimLink.indexOf("id=") === 0 || claimLink.indexOf("bundle=") === 0) {
            query = claimLink
        } else {
            selectedAirdropId = claimLink
            airdropName = claimLink
            claimBundleOverride = ""
            resetClaimEligibility()
            resetClaimantBalance()
            if (screen === "claim") Qt.callLater(refreshClaimEligibility)
            return true
        }

        var id = claimLinkParam(query, "id")
        var bundle = claimLinkParam(query, "bundle")
        if (id === "") {
            claimLinkError = "Claim link is missing a distribution id."
            return false
        }
        selectedAirdropId = id
        airdropName = id
        claimBundleOverride = bundle
        resetClaimEligibility()
        resetClaimantBalance()
        if (screen === "claim") Qt.callLater(refreshClaimEligibility)
        return true
    }

    function resetClaimEligibility() {
        claimEligibilityStatus = "unchecked"
        claimEligibilityError = ""
        claimEligibilityAmount = ""
        claimEligibilityBucket = -1
        claimEligibilityNullifier = ""
        lastProofPath = ""
        lastProofDurationSeconds = 0
        lastClaimTxId = ""
        lastTokenSettlementTxId = ""
        lastClaimAmount = ""
        duplicateClaimStatus = ""
        if (!sampleRunning) {
            sampleStatus = "Ready to claim"
            sampleError = ""
        }
    }

    function claimEligibilityLabel() {
        if (claimEligibilityStatus === "claimed") return "claimed"
        if (claimEligibilityStatus === "eligible") return "eligible"
        if (claimEligibilityStatus === "checking") return "checking"
        if (claimEligibilityStatus === "rejected") return "not eligible"
        return "unchecked"
    }

    function claimAlreadyClaimed() {
        var text = String(sampleError || "") + "\n" + String(claimEligibilityError || "")
        text = text.toLowerCase()
        return claimEligibilityStatus === "claimed"
            || text.indexOf("already claimed") !== -1
            || text.indexOf("e_already_claimed") !== -1
    }

    function resetClaimantBalance() {
        claimantTokenBalance = ""
        claimantTokenBalanceError = ""
        claimantTokenBalanceAccount = ""
        claimantTokenBalanceTokenId = ""
        claimantTokenBalanceAirdrop = ""
        claimantTokenBalanceClaimKey = ""
        claimantTokenBalanceNullifier = ""
    }

    function claimantBalanceMatchesCurrentClaim() {
        return claimantTokenBalance !== ""
            && claimantTokenBalanceAccount === claimantBalanceAccount
            && claimantTokenBalanceTokenId === activeTokenId()
            && claimantTokenBalanceAirdrop === claimAirdropName()
            && claimantTokenBalanceClaimKey === claimantPubkey
            && claimantTokenBalanceNullifier === claimEligibilityNullifier
    }

    function claimantBalanceCanShowTokenBalance() {
        if (!claimantBalanceMatchesCurrentClaim()) return false
        if (claimEligibilityStatus === "claimed") return true
        return lastClaimTxId !== ""
            && claimEligibilityNullifier !== ""
            && claimantTokenBalanceNullifier === claimEligibilityNullifier
    }

    function claimantBalanceText() {
        if (!customTokenSettlementConfigured()) {
            if (claimEligibilityStatus === "claimed" || lastClaimTxId !== "") return "Native payout confirmed"
            return "Native payout"
        }
        if (claimantTokenBalanceError !== "") return "unavailable"
        if (claimantBalanceCanShowTokenBalance()) return claimantTokenBalance + " tokens"
        if (claimEligibilityStatus === "eligible" || claimEligibilityStatus === "checking") return "0 tokens"
        if (claimEligibilityStatus === "claimed" && claimantBalanceAccount !== "") return "loading"
        if (claimantBalanceAccount !== "") return "not checked"
        if (destinationPacket !== "") return "loading"
        return "-"
    }

    function scheduleClaimPageRefresh() {
        if (screen !== "claim" || sampleRunning) return
        claimPageRefreshTimer.restart()
    }

    function refreshClaimPage() {
        if (destinationPacket !== "" && destinationCommitment === "") {
            if (!loadDestinationPacket(destinationPacket, false, false)) return false
        }
        return queryClaimantBalance()
    }

    function rememberEligibility(parsed) {
        if (!parsed) return
        claimEligibilityStatus = "eligible"
        claimEligibilityError = ""
        claimEligibilityAmount = parsed.amount_raw !== undefined ? String(parsed.amount_raw) : String(parsed.amount)
        claimEligibilityBucket = parsed.amount_bucket !== undefined ? Number(parsed.amount_bucket) : -1
        claimEligibilityNullifier = parsed.nullifier ? String(parsed.nullifier) : ""
    }

    function refreshClaimEligibility() {
        if (claimantPubkey === "") {
            claimEligibilityStatus = "rejected"
            claimEligibilityError = "Load a DistributionX claim key seed before checking eligibility."
            claimEligibilityAmount = ""
            claimEligibilityBucket = -1
            claimEligibilityNullifier = ""
            return false
        }
        if (destinationPacket === "") {
            claimEligibilityStatus = "rejected"
            claimEligibilityError = "Load a destination packet before checking eligibility."
            claimEligibilityAmount = ""
            claimEligibilityBucket = -1
            claimEligibilityNullifier = ""
            return false
        }
        if (!canClaim) {
            claimEligibilityStatus = "rejected"
            claimEligibilityError = "Confirm the destination recovery backup before checking eligibility."
            claimEligibilityAmount = ""
            claimEligibilityBucket = -1
            claimEligibilityNullifier = ""
            return false
        }

        claimEligibilityStatus = "checking"
        claimEligibilityError = ""
        if (!sampleRunning) sampleError = ""
        activeOperation = "checking eligibility"
        var response = callClientForStep("checking eligibility", "checkEligibility", [claimAirdropName(), claimBundlePath(), walletSeedPath(), destinationPacket])
        if (debugUiEnabled) sampleDetail += "Eligibility check: " + String(response) + "\n"
        var parsed = parseClientJson(response)
        if (!parsed || parsed.status !== "ELIGIBILITY_OK") {
            claimEligibilityAmount = ""
            claimEligibilityBucket = -1
            claimEligibilityNullifier = ""
            claimEligibilityError = parsed && parsed.error ? String(parsed.error) : friendlyError(response)
            claimEligibilityStatus = claimAlreadyClaimed() ? "claimed" : "rejected"
            if (!sampleRunning) sampleError = claimEligibilityError
            if (claimEligibilityStatus === "claimed") Qt.callLater(queryClaimantBalance)
            activeOperation = ""
            return false
        }
        rememberEligibility(parsed)
        Qt.callLater(queryClaimantBalance)
        if (!sampleRunning) sampleError = ""
        activeOperation = ""
        return true
    }

    function claimConfigurationError() {
        var missing = []
        if (destinationPacket === "") missing.push("PRIVATE_DESTINATION_FILE")
        if (serializedLezTxPath === "") missing.push("DISTRIBUTIONX_SERIALIZED_LEZ_TX")
        if (relayerUrl === "") missing.push("DISTRIBUTIONX_RELAYER_URL")
        if (!claimSubmitCommandConfigured) missing.push("DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND")
        if (missing.length === 0) return ""
        return "Configuration error: set " + missing.join(", ") + " before claiming."
    }

    function friendlyError(response) {
        var text = String(response).trim()
        var stepClause = activeOperation !== "" ? " while " + activeOperation : ""
        try {
            var parsed = JSON.parse(text)
            if (typeof parsed === "string") return friendlyError(parsed)
            if (parsed.error) return friendlyError(String(parsed.error))
            if (parsed.output) return friendlyError(parsed.output)
            if (parsed.status && parsed.status !== "DISTRIBUTIONX_CLIENT_ERROR") return String(parsed.status)
        } catch (e) {
        }
        if (text.indexOf("E_AIRDROP_ID_MISMATCH") !== -1) {
            if (actionJobKind === "fund" || activeOperation.indexOf("fund") !== -1) {
                return "The selected distribution does not match the initialized local state. Re-initialize this distribution, then fund it."
            }
            if (actionJobKind === "initDistribution" || activeOperation.indexOf("initializ") !== -1) {
                return "The selected distribution does not match the local state. Restart with --reset-localnet --clean-user-dir and initialize again."
            }
            if (samplePendingOperation === "checkEligibility" || activeOperation.indexOf("eligibility") !== -1) {
                return "The selected bundle does not match this distribution."
            }
            return "This proof was generated for a different distribution. Generate a fresh proof for the selected distribution."
        }
        if (text.indexOf("E_RISC0_PROVE") !== -1 && text.indexOf("Some(125)") !== -1) {
            return "Docker could not start the proof finalizer. Close Basecamp, restart DistributionX with the launcher, then retry. Your claim was not submitted."
        }
        if (text.indexOf("E_RISC0_PROVE") !== -1) {
            return "Private proof generation failed before submission. Check the Risc0 and Docker setup, then retry."
        }
        if (text.indexOf("E_RECEIPT_JOURNAL_MISMATCH") !== -1) {
            return "The proof receipt does not match the claim data. Generate a fresh proof."
        }
        if (text.indexOf("E_RECEIPT_VERIFY") !== -1) {
            return "Proof verification failed. Generate a fresh proof."
        }
        if (text.indexOf("E_RECEIPT_MODE") !== -1) {
            return "Proof mode is not the required Risc0 receipt. Generate a real proof with RISC0_DEV_MODE=0."
        }
        if (text.indexOf("E_PROGRAM_3") !== -1) {
            return "This proof does not match the current distribution. Generate a fresh proof."
        }
        if (text.indexOf("E_PROGRAM_1") !== -1) {
            return "This distribution is closed."
        }
        if (text.indexOf("E_PROGRAM_2") !== -1) {
            return "The selected bundle does not match this distribution."
        }
        if (text.indexOf("E_PROGRAM_4") !== -1) {
            return "The selected bundle uses an unsupported claim amount bucket."
        }
        if (text.indexOf("E_PROGRAM_5") !== -1) {
            return "Proof verification failed. Generate a real proof with RISC0_DEV_MODE=0."
        }
        if (text.indexOf("E_PROGRAM_7") !== -1) {
            return "This distribution is not funded enough for this claim."
        }
        if (text.indexOf("E_DISTRIBUTIONX_TX_REJECTED") !== -1) {
            return "The local sequencer rejected the claim transaction. Restart with --reset-localnet --clean-user-dir and try the claim again."
        }
        if (text.indexOf("E_DISTRIBUTIONX_TX_NOT_INCLUDED") !== -1) {
            return "The claim transaction was submitted but not confirmed before the timeout."
        }
        if (text.indexOf("E_DISTRIBUTIONX_PRIVATE_CLAIM_PAYLOAD_MISSING") !== -1) {
            return "The shielded claim payload is missing. Generate a fresh proof, then claim again."
        }
        if (text.indexOf("E_DISTRIBUTIONX_PRIVATE_CLAIM_REQUIRED") !== -1) {
            return "This flow requires a shielded claim payload. Load a destination packet and generate a fresh proof."
        }
        if (text.indexOf("E_ALREADY_CLAIMED") !== -1) {
            return "This wallet has already claimed this distribution."
        }
        if (text.indexOf("E_WALLET_NOT_ELIGIBLE") !== -1) {
            return "This wallet is not eligible for the selected distribution."
        }
        if (text.indexOf("E_WALLET_SEED_NOT_FOUND") !== -1) {
            return "Load a DistributionX claim key seed before claiming."
        }
        if (text.indexOf("E_WALLET_SEED_INVALID") !== -1) {
            return "The selected claim key seed is not valid."
        }
        if (text.indexOf("E_BUNDLE_NOT_FOUND") !== -1) {
            return "The selected bundle file does not exist."
        }
        if (text.indexOf("E_BUNDLE_INVALID") !== -1) {
            return "The selected bundle file is not a valid DistributionX bundle."
        }
        if (text.indexOf("E_DESTINATION_PACKET_NOT_FOUND") !== -1) {
            return "The destination packet file does not exist."
        }
        if (text.indexOf("E_DESTINATION_PACKET_INVALID") !== -1) {
            return "The destination packet is not a valid shielded destination file."
        }
        if (text.indexOf("E_TESTNET_RPC_REQUIRED") !== -1) {
            return "Configuration error: set LEZ_RPC_URL before initializing a distribution."
        }
        if (text.indexOf("E_DISTRIBUTIONX_DEPLOYMENT_MISSING") !== -1 || text.indexOf("deployment.json") !== -1) {
            return isLocalRpc()
                ? "The local DistributionX program has not been deployed yet. Restart the local sequencer and try Initialize again."
                : "Deploy DistributionX before initializing this distribution."
        }
        if (text.indexOf("E_DISTRIBUTIONX_LOCALNET_RPC_NOT_READY") !== -1) {
            return "The local LEZ sequencer is not reachable at " + testnetRpc + ". Start the sequencer, then try Initialize again."
        }
        if (text.indexOf("E_LEZ_DEPLOY_COMMAND_REQUIRED") !== -1) {
            return "The local deploy tool is not available. Run the Basecamp launcher from the prepared dev environment, then try Initialize again."
        }
        if (text.indexOf("signing key not found") !== -1) {
            return "This distributor account is not in the local LEZ wallet. Use an account from the configured LEE_WALLET_HOME_DIR."
        }
        if (text.indexOf("E_DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND_REQUIRED") !== -1) {
            return "Configuration error: set DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND before submitting the claim."
        }
        if (text.indexOf("E_EMPTY_SERIALIZED_LEZ_TX") !== -1) {
            return "Configuration error: DISTRIBUTIONX_SERIALIZED_LEZ_TX points to an empty transaction file."
        }
        if (text.indexOf("E_SERIALIZED_LEZ_TX_NOT_FOUND") !== -1) {
            return isLocalRpc()
                ? "Local claim transaction could not be prepared."
                : "Configuration error: DISTRIBUTIONX_SERIALIZED_LEZ_TX does not exist."
        }
        if (text.indexOf("Invalid response") !== -1) {
            return "The DistributionX helper did not return a valid response" + stepClause + "."
        }
        if (text.indexOf("DISTRIBUTIONX_CLIENT_ERROR") !== -1) {
            return "The local DistributionX helper could not complete this step" + stepClause + "."
        }
        return text
    }

    function destinationCommitmentFromResponse(response) {
        var parsed = parseClientJson(response)
        if (parsed && parsed.claim_destination_commitment !== undefined) {
            return String(parsed.claim_destination_commitment)
        }
        var match = /"claim_destination_commitment"\s*:\s*"([^"]+)"/.exec(String(response))
        return match && match.length > 1 ? String(match[1]) : ""
    }

    function loadDestinationPacket(path, refreshEligibility, refreshBalance) {
        var shouldRefreshEligibility = refreshEligibility !== false
        var shouldRefreshBalance = refreshBalance !== false
        sampleError = ""
        var response = callClient("loadDestinationPacket", [path])
        sampleDetail += "Destination packet: " + String(response) + "\n"
        if (!responseHas(response, "DESTINATION_PACKET_OK")) {
            var loadError = friendlyError(response)
            sampleError = loadError
            destinationCommitment = ""
            resetClaimEligibility()
            claimantTokenBalance = ""
            claimantTokenBalanceError = loadError
            return false
        }
        destinationMode = "external-wallet"
        destinationPacket = path
        recoveryGateStatus = "attested"
        backupAttestedAt = new Date().toISOString()
        var commitment = destinationCommitmentFromResponse(response)
        if (commitment === "") {
            var parseError = "Destination packet did not return a destination account."
            sampleError = parseError
            destinationCommitment = ""
            claimantTokenBalance = ""
            claimantTokenBalanceError = parseError
            return false
        }
        destinationCommitment = commitment
        if (shouldRefreshBalance) Qt.callLater(queryClaimantBalance)
        if (shouldRefreshEligibility && screen === "claim") Qt.callLater(refreshClaimEligibility)
        return true
    }

    function clearActionJob() {
        actionJobId = ""
        actionJobKind = ""
        actionJobMarker = ""
        actionJobLabel = ""
        activeOperation = ""
    }

    function startActionJob(kind, label, method, args, marker) {
        if (actionJobId !== "") return false
        activeOperation = label
        actionJobKind = kind
        actionJobMarker = marker
        actionJobLabel = label
        var response = callClient(method, args)
        if (!responseHas(response, "JOB_STARTED")) {
            distributorError = friendlyError(response)
            if (kind === "createWallet") claimantWalletError = distributorError
            clearActionJob()
            return false
        }
        var parsed = parseClientJson(response)
        if (!parsed || !parsed.job_id) {
            distributorError = friendlyError(response)
            if (kind === "createWallet") claimantWalletError = distributorError
            clearActionJob()
            return false
        }
        actionJobId = String(parsed.job_id)
        actionJobTimer.restart()
        return true
    }

    function failActionJob(output) {
        var message = friendlyError(output)
        if (actionJobKind === "createWallet") {
            claimantWalletError = message
        } else {
            distributorStatus = "Setup failed"
            distributorError = message
            sampleError = message
        }
        clearActionJob()
        return false
    }

    function completeActionJob(output) {
        sampleDetail += actionJobLabel + ": " + String(output) + "\n"
        if (!responseHas(output, actionJobMarker)) {
            return failActionJob(output)
        }
        var parsed = parseClientJson(output)
        if ((actionJobKind === "initDistribution" || actionJobKind === "fund" || actionJobKind === "createWallet" || actionJobKind === "tokenId" || actionJobKind === "mintToken") && !parsed) {
            return failActionJob(output)
        }
        if (actionJobKind === "sampleFixture") {
            distributorError = ""
            sampleError = ""
            if (parsed && parsed.admin_account !== undefined) {
                recoveryAddress = String(parsed.admin_account)
            }
            eligibilityCsvPath = distributionStateDir + "/eligible.csv"
            destinationPacket = distributionStateDir + "/shielded_destination.json"
            if (!loadDestinationPacket(destinationPacket)) {
                clearActionJob()
                return false
            }
            validateCsv(eligibilityCsvPath)
            if (lastCsvInspection && lastCsvInspection.total_amount !== undefined) {
                fundAmount = String(lastCsvInspection.total_amount)
            }
            distributorStatus = "Sample CSV ready"
        } else if (actionJobKind === "initDistribution") {
            rememberInitReceipt(parsed)
            distributorStatus = "Distribution initialized"
            distributorError = ""
            sampleError = ""
            refreshAirdrops()
        } else if (actionJobKind === "fund") {
            rememberFundReceipt(parsed)
            distributorStatus = "Distribution funded"
            distributorError = ""
            sampleError = ""
            refreshAirdrops()
        } else if (actionJobKind === "createWallet") {
            claimantPubkey = parsed.account
            resetClaimEligibility()
            resetClaimantBalance()
            if (screen === "claim") Qt.callLater(refreshClaimEligibility)
            distributorStatus = "Claim key saved"
            distributorError = ""
            claimantWalletError = ""
        } else if (actionJobKind === "tokenId") {
            tokenId = parsed.token_id
            distributorStatus = payoutMode === "native" ? "Native asset label ready" : "Token id ready"
            distributorError = ""
        } else if (actionJobKind === "mintToken") {
            payoutMode = "custom"
            tokenId = parsed.token_id
            tokenSourceAccount = parsed.supply_account_id
            distributorStatus = "Token minted"
            distributorError = ""
            Qt.callLater(queryDistributorBalance)
        }
        clearActionJob()
        return true
    }

    function pollActionJob() {
        if (actionJobId === "") {
            actionJobTimer.stop()
            return
        }
        var response = callClient("jobStatus", [actionJobId])
        if (responseHas(response, "JOB_RUNNING")) return
        actionJobTimer.stop()
        var parsed = parseClientJson(response)
        var output = parsed && parsed.output !== undefined ? String(parsed.output) : String(response)
        completeActionJob(output)
    }

    function prepareSampleFixture() {
        sampleError = ""
        distributorError = ""
        distributorStatus = "Preparing eligibility list"
        return startActionJob("sampleFixture", "preparing sample csv", "startSampleFixture", [distributionStateDir], "SAMPLE_FIXTURE_OK")
    }

    function initializeDistribution() {
        sampleError = ""
        distributorError = ""
        if (testnetRpc === "" || distributorAccount === "" || tokenId === "" || recoveryAddress === "" || eligibilityCsvPath === "") {
            distributorStatus = "Setup failed"
            distributorError = "Configuration error: set LEZ_RPC_URL, LEZ_DEPLOYER_WALLET, DISTRIBUTIONX_TOKEN_ID, DISTRIBUTIONX_RECOVERY_ADDRESS, and the eligibility CSV path."
            sampleError = distributorError
            return false
        }
        if (payoutMode === "custom" && tokenSourceAccount === "") {
            distributorStatus = "Setup failed"
            distributorError = "Custom token mode requires a token supply account. Mint a token or paste its source account."
            sampleError = distributorError
            return false
        }
        distributorStatus = "Initializing distribution"
        return startActionJob("initDistribution", "initializing the distribution", "startInitDistribution", [eligibilityCsvPath, distributorAccount, tokenId, tokenSourceAccount, testnetRpc, expiryUnix, recoveryAddress], "INIT_OK")
    }

    function queryDistributorBalance() {
        distributorTokenBalance = ""
        distributorTokenBalanceError = ""
        var sourceAccount = activeTokenSourceAccount()
        if (testnetRpc === "" || sourceAccount === "" || activeTokenId() === "") return false

        var response = callClient("queryTokenBalance", [testnetRpc, sourceAccount, activeTokenId()])
        var parsed = parseClientJson(response)
        if (!parsed || parsed.status !== "QUERY_BALANCE_OK") {
            distributorTokenBalanceError = parsed && parsed.error ? String(parsed.error) : friendlyError(response)
            return false
        }
        if (parsed.balance === undefined) {
            distributorTokenBalanceError = "Balance response missing balance."
            return false
        }
        distributorTokenBalance = String(parsed.balance)
        return true
    }

    function queryClaimantBalance() {
        claimantTokenBalance = ""
        claimantTokenBalanceError = ""
        if (!customTokenSettlementConfigured()) return true
        if (testnetRpc === "") {
            claimantTokenBalanceError = "LEZ RPC URL is not configured."
            return false
        }
        if (claimantBalanceAccount === "") {
            if (destinationPacket !== "") {
                if (!loadDestinationPacket(destinationPacket, false, false)) return false
            }
            if (claimantBalanceAccount === "") {
                claimantTokenBalanceError = "Destination packet did not return a destination account."
                return false
            }
        }

        var balanceToken = activeTokenId()
        if (balanceToken === "") {
            claimantTokenBalanceError = "Token id is not configured for this distribution."
            return false
        }
        var response = callClient("queryTokenBalance", [testnetRpc, claimantBalanceAccount, balanceToken])
        var parsed = parseClientJson(response)
        if (!parsed || parsed.status !== "QUERY_BALANCE_OK") {
            claimantTokenBalanceError = parsed && parsed.error ? String(parsed.error) : friendlyError(response)
            return false
        }
        if (parsed.balance === undefined) {
            claimantTokenBalanceError = "Balance response missing balance."
            return false
        }
        claimantTokenBalance = String(parsed.balance)
        claimantTokenBalanceAccount = claimantBalanceAccount
        claimantTokenBalanceTokenId = balanceToken
        claimantTokenBalanceAirdrop = claimAirdropName()
        claimantTokenBalanceClaimKey = claimantPubkey
        claimantTokenBalanceNullifier = claimEligibilityNullifier
        return true
    }

    function createWallet() {
        distributorError = ""
        claimantWalletError = ""
        return startActionJob("createWallet", "creating claim key", "startCreateWallet", [distributionStateDir], "CREATE_WALLET_OK")
    }

    function useConfiguredDistributor() {
        if (configuredDistributorAccount === "") return false
        distributorAccount = configuredDistributorAccount
        distributorStatus = "Local signer selected"
        distributorError = ""
        return true
    }

    function generateNativeTokenId() {
        distributorError = ""
        distributorStatus = "Creating native asset label"
        return startActionJob("tokenId", "creating native asset label", "startTokenId", [airdropName !== "" ? airdropName + "-compatibility-token" : "native-lez-compatibility-token"], "TOKEN_ID_OK")
    }

    function ensureNativePayoutReady() {
        if (payoutMode !== "native") return true
        tokenSourceAccount = ""
        if (tokenId !== "") return true
        if (actionRunning) return false
        return generateNativeTokenId()
    }

    function selectNativePayout() {
        if (actionRunning) return false
        payoutMode = "native"
        tokenId = ""
        tokenSourceAccount = ""
        return ensureNativePayoutReady()
    }

    function selectCustomPayout() {
        if (actionRunning) return false
        payoutMode = "custom"
        tokenId = ""
        tokenSourceAccount = ""
        distributorStatus = "Custom token selected"
        distributorError = ""
        return true
    }

    function mintTokenSupply() {
        if (lastCsvInspection && lastCsvInspection.total_amount !== undefined) return String(lastCsvInspection.total_amount)
        if (fundAmount !== "") return fundAmount
        return "3000"
    }

    function mintDistributionToken() {
        distributorError = ""
        distributorStatus = "Minting token"
        return startActionJob("mintToken", "minting token", "startMintToken", [airdropName !== "" ? airdropName + "-token" : "distributionx-token", mintTokenSupply()], "TOKEN_MINTED")
    }

    property var lastCsvInspection: null
    property string csvInspectError: ""
    property bool csvValidationRunning: false
    property string csvValidationJobId: ""
    property string csvValidationPath: ""
    // Claimant identity state — derived from $DISTRIBUTIONX_STATE_DIR/wallet.seed
    property string claimantPubkey: ""
    property string claimantWalletError: ""
    property string lezWalletStatus: "unchecked"
    property string lezWalletMessage: "LEZ wallet module not checked"
    property int lezWalletAccountCount: 0
    property var lezWalletAccounts: []

    function walletSeedPath() {
        return distributionStateDir + "/wallet.seed"
    }

    function valueToArray(value) {
        if (Array.isArray(value)) return value
        if (value && typeof value !== "string" && typeof value.length === "number") {
            var out = []
            for (var i = 0; i < value.length; i++) out.push(value[i])
            return out
        }
        var parsed = parseClientJson(value)
        if (Array.isArray(parsed)) return parsed
        if (parsed && parsed.accounts && Array.isArray(parsed.accounts)) return parsed.accounts
        return null
    }

    function callOptionalModule(moduleName, method, args) {
        if (!hasBridge()) {
            return { ok: false, error: "Basecamp bridge is not available." }
        }
        try {
            return { ok: true, response: logos.callModule(moduleName, method, args) }
        } catch (e) {
            return { ok: false, error: String(e) }
        }
    }

    function refreshLezWalletStatus() {
        var result = callOptionalModule("lez_wallet_module", "list_accounts", [])
        if (!result.ok) {
            lezWalletStatus = "unavailable"
            lezWalletAccountCount = 0
            lezWalletAccounts = []
            lezWalletMessage = "LEZ wallet module is not loaded in Basecamp."
            return false
        }
        var responseText = String(result.response)
        if (responseText.indexOf("Invalid response") !== -1
                || responseText.indexOf("not loaded") !== -1
                || responseText.indexOf("not found") !== -1) {
            lezWalletStatus = "unavailable"
            lezWalletAccountCount = 0
            lezWalletAccounts = []
            lezWalletMessage = "LEZ wallet module is not loaded in Basecamp."
            return false
        }
        var accounts = valueToArray(result.response)
        if (!accounts) {
            lezWalletStatus = "unreadable"
            lezWalletAccountCount = 0
            lezWalletAccounts = []
            lezWalletMessage = "LEZ wallet module responded, but DistributionX could not read its account list."
            return false
        }
        lezWalletStatus = "loaded"
        lezWalletAccounts = accounts
        lezWalletAccountCount = accounts.length
        lezWalletMessage = accounts.length > 0
            ? "LEZ wallet module loaded. Its current API exposes accounts and transfers; DistributionX claims still use the DistributionX claim key."
            : "LEZ wallet module loaded. No LEZ accounts were returned."
        return true
    }

    function refreshClaimantPubkey() {
        claimantWalletError = ""
        var response = callClient("walletPublicKey", [walletSeedPath()])
        var parsed = parseClientJson(response)
        if (!parsed || parsed.status !== "WALLET_PUBKEY_OK") {
            claimantPubkey = ""
            claimantWalletError = friendlyError(response)
            resetClaimEligibility()
            resetClaimantBalance()
            return false
        }
        var pubkey = parsed.pubkey_lez ? String(parsed.pubkey_lez) : String(parsed.pubkey)
        if (claimantPubkey !== pubkey) {
            resetClaimEligibility()
            resetClaimantBalance()
        }
        claimantPubkey = pubkey
        if (screen === "claim") Qt.callLater(refreshClaimEligibility)
        return true
    }

    function importClaimantWallet(srcPath) {
        claimantWalletError = ""
        var response = callClient("setWallet", [srcPath, walletSeedPath()])
        var parsed = parseClientJson(response)
        if (!parsed || parsed.status !== "SET_WALLET_OK") {
            claimantWalletError = friendlyError(response)
            resetClaimEligibility()
            resetClaimantBalance()
            return false
        }
        var pubkey = parsed.pubkey_lez ? String(parsed.pubkey_lez) : String(parsed.pubkey)
        if (claimantPubkey !== pubkey) {
            resetClaimEligibility()
            resetClaimantBalance()
        }
        claimantPubkey = pubkey
        if (screen === "claim") Qt.callLater(refreshClaimEligibility)
        return true
    }

    function applyCsvInspectionResponse(response) {
        var parsed = parseClientJson(response)
        if (!parsed || !parsed.status) {
            csvInspectError = friendlyError(response)
            lastCsvInspection = null
            return false
        }
        if (parsed.status !== "CSV_OK") {
            csvInspectError = parsed.error ? String(parsed.error) : "CSV validation failed."
            lastCsvInspection = parsed
            return false
        }
        lastCsvInspection = parsed
        return true
    }

    function validateCsv(path) {
        csvInspectError = ""
        if (path === "") {
            csvInspectError = "No CSV path set."
            lastCsvInspection = null
            return false
        }
        var response = callClientForStep("validating the CSV", "inspectCsv", [path])
        var ok = applyCsvInspectionResponse(response)
        activeOperation = ""
        return ok
    }

    function startCsvValidation(path) {
        if (csvValidationRunning) return false
        csvInspectError = ""
        lastCsvInspection = null
        if (path === "") {
            csvInspectError = "No CSV path set."
            return false
        }
        activeOperation = "validating the CSV"
        csvValidationRunning = true
        csvValidationPath = path
        var response = callClient("startInspectCsv", [path])
        if (!responseHas(response, "JOB_STARTED")) {
            csvValidationRunning = false
            csvValidationPath = ""
            activeOperation = ""
            csvInspectError = friendlyError(response)
            return false
        }
        var parsed = parseClientJson(response)
        if (!parsed || !parsed.job_id) {
            csvValidationRunning = false
            csvValidationPath = ""
            activeOperation = ""
            csvInspectError = friendlyError(response)
            return false
        }
        csvValidationJobId = String(parsed.job_id)
        csvValidationTimer.restart()
        return true
    }

    function pollCsvValidationJob() {
        if (!csvValidationRunning || csvValidationJobId === "") {
            csvValidationTimer.stop()
            return
        }
        var response = callClient("jobStatus", [csvValidationJobId])
        if (responseHas(response, "JOB_RUNNING")) return

        csvValidationTimer.stop()
        csvValidationRunning = false
        csvValidationJobId = ""
        activeOperation = ""
        var parsed = parseClientJson(response)
        var output = parsed && parsed.output !== undefined ? String(parsed.output) : String(response)
        if (csvValidationPath !== eligibilityCsvPath) {
            csvValidationPath = ""
            csvInspectError = "CSV path changed. Validate again."
            lastCsvInspection = null
            return
        }
        csvValidationPath = ""
        applyCsvInspectionResponse(output)
    }

    function fundDistribution() {
        sampleError = ""
        distributorError = ""
        if (fundAmount === "") {
            distributorStatus = "Setup failed"
            distributorError = "Configuration error: set DISTRIBUTIONX_FUND_AMOUNT before funding."
            sampleError = distributorError
            return false
        }
        distributorStatus = "Funding distribution"
        var fundAirdrop = lastAirdropId !== "" ? lastAirdropId : airdropName
        return startActionJob("fund", "funding the distribution", "startFund", [fundAirdrop, fundAmount], "FUND_OK")
    }

    function startProofTimer() {
        proofStartedAtMs = Date.now()
        proofElapsedSeconds = 0
        lastProofDurationSeconds = 0
        proofTimer.restart()
    }

    function stopProofTimer() {
        if (proofStartedAtMs > 0) {
            proofElapsedSeconds = Math.max(1, Math.floor((Date.now() - proofStartedAtMs) / 1000))
            lastProofDurationSeconds = proofElapsedSeconds
        }
        proofTimer.stop()
        proofStartedAtMs = 0
    }

    function formatElapsed(seconds) {
        if (seconds <= 0) return "00:00"
        var m = Math.floor(seconds / 60)
        var s = seconds % 60
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }

    function rememberInitReceipt(parsed) {
        if (!parsed) return
        if (parsed.airdrop_id) {
            lastAirdropId = String(parsed.airdrop_id)
            selectedAirdropId = lastAirdropId
        }
        if (parsed.tx_id) lastInitTxId = String(parsed.tx_id)
        if (parsed.bundle_path) lastBundlePath = String(parsed.bundle_path)
        if (parsed.eligible_count !== undefined) lastEligibleCount = Number(parsed.eligible_count) || 0
        lastFundedAmount = ""
        lastFundTxId = ""
        lastTotalFunded = 0
        lastTotalClaimed = 0
        lastClaimTxId = ""
        lastTokenSettlementTxId = ""
        lastClaimAmount = ""
        lastProofPath = ""
        lastProofDurationSeconds = 0
    }

    function rememberFundReceipt(parsed) {
        if (!parsed) return
        if (parsed.amount !== undefined) lastFundedAmount = String(parsed.amount)
        if (parsed.tx_id) lastFundTxId = String(parsed.tx_id)
        if (parsed.total_funded !== undefined) lastTotalFunded = Number(parsed.total_funded) || 0
    }

    function rememberProveReceipt(parsed) {
        if (!parsed) return
        if (parsed.proof) lastProofPath = String(parsed.proof)
        if (parsed.serialized_lez_tx) serializedLezTxPath = String(parsed.serialized_lez_tx)
    }

    function rememberClaimReceipt(parsed) {
        if (!parsed) return
        if (parsed.tx_id) lastClaimTxId = String(parsed.tx_id)
        lastTokenSettlementTxId = parsed.token_tx_id ? String(parsed.token_tx_id) : ""
        if (parsed.amount !== undefined) lastClaimAmount = String(parsed.amount)
        if (parsed.total_claimed !== undefined) lastTotalClaimed = Number(parsed.total_claimed) || 0
        claimEligibilityStatus = "claimed"
        claimEligibilityError = ""
        if (parsed.amount !== undefined) claimEligibilityAmount = String(parsed.amount)
        if (customTokenSettlementConfirmed()) Qt.callLater(queryClaimantBalance)
    }

    function maybeFinishAutoRunSample() {
        if (!autoQuitAfterSample) return
        console.log("DISTRIBUTIONX_AUTO_RUN_SAMPLE_RESULT", claimCompleted(), sampleStatus)
        console.log("DISTRIBUTIONX_AUTO_RUN_SAMPLE_ERROR", sampleError)
        console.log("DISTRIBUTIONX_AUTO_RUN_SAMPLE_DETAIL", sampleDetail)
        Qt.callLater(Qt.quit)
    }

    function failSampleStep(response) {
        sampleError = friendlyError(response)
        sampleStatus = "Claim failed"
        sampleRunning = false
        samplePendingJobId = ""
        samplePendingMarker = ""
        samplePendingOperation = ""
        sampleJobTimer.stop()
        stopProofTimer()
        maybeFinishAutoRunSample()
        return false
    }

    function completeSampleStep(step, response) {
        sampleDetail += step[3] + ": " + String(response) + "\n"
        if (!responseHas(response, step[2])) {
            return failSampleStep(response)
        }
        var parsed = parseClientJson(response)
        var operation = step.length > 4 ? step[4] : step[0]
        var trustMutating = operation === "initDistribution" || operation === "fund" || operation === "claim"
        var mustParse = trustMutating || operation === "checkEligibility"
        if (mustParse && !parsed) {
            return failSampleStep(response)
        }
        if (operation === "sampleFixture") {
            eligibilityCsvPath = distributionStateDir + "/eligible.csv"
            destinationPacket = distributionStateDir + "/shielded_destination.json"
            if (parsed && parsed.admin_account !== undefined) {
                recoveryAddress = String(parsed.admin_account)
            }
            if (parsed && parsed.claimant_count !== undefined) {
                fundAmount = String(Number(parsed.claimant_count) * 100)
            }
            if (!loadDestinationPacket(destinationPacket) || !canClaim) {
                sampleStatus = "Claim failed"
                sampleRunning = false
                stopProofTimer()
                maybeFinishAutoRunSample()
                return false
            }
        }
        if (operation === "initDistribution") rememberInitReceipt(parsed)
        if (operation === "fund") rememberFundReceipt(parsed)
        if (operation === "checkEligibility") rememberEligibility(parsed)
        if (operation === "claim") rememberClaimReceipt(parsed)
        activeOperation = ""
        return true
    }

    function runNextSampleStep() {
        if (!sampleRunning) return
        if (sampleStepIndex >= sampleSteps.length) {
            sampleStatus = claimCompletionStatus()
            sampleRunning = false
            activeOperation = ""
            refreshAirdrops()
            if (customTokenSettlementConfirmed()) Qt.callLater(queryClaimantBalance)
            maybeFinishAutoRunSample()
            return
        }

        var step = sampleSteps[sampleStepIndex]
        sampleStatus = step[3]
        activeOperation = step[3].toLowerCase()
        if (String(step[0]).indexOf("start") === 0) {
            var started = callClient(step[0], step[1])
            sampleDetail += step[3] + ": " + String(started) + "\n"
            if (!responseHas(started, "JOB_STARTED")) {
                failSampleStep(started)
                return
            }
            var parsed = parseClientJson(started)
            if (!parsed || !parsed.job_id) {
                failSampleStep(started)
                return
            }
            samplePendingJobId = String(parsed.job_id)
            samplePendingMarker = step[2]
            samplePendingOperation = step.length > 4 ? step[4] : step[0]
            if (step[0] === "startProve") startProofTimer()
            sampleJobTimer.restart()
            return
        }

        var response = callClient(step[0], step[1])
        if (!completeSampleStep(step, response)) return
        sampleStepIndex += 1
        Qt.callLater(runNextSampleStep)
    }

    function pollSampleJob() {
        if (!sampleRunning || samplePendingJobId === "") {
            sampleJobTimer.stop()
            return
        }

        var response = callClient("jobStatus", [samplePendingJobId])
        if (responseHas(response, "JOB_RUNNING")) return

        sampleJobTimer.stop()
        var parsed = parseClientJson(response)
        var output = parsed && parsed.output !== undefined ? String(parsed.output) : String(response)
        if (!responseHas(output, samplePendingMarker)) {
            failSampleStep(output)
            return
        }

        var outputParsed = parseClientJson(output)
        if (samplePendingMarker === "PROVE_LOCAL_OK") {
            if (!outputParsed) {
                failSampleStep(output)
                return
            }
            rememberProveReceipt(outputParsed)
        }

        var completedStep = [samplePendingOperation, [], samplePendingMarker, sampleStatus, samplePendingOperation]
        if (!completeSampleStep(completedStep, output)) return
        samplePendingJobId = ""
        samplePendingMarker = ""
        samplePendingOperation = ""
        stopProofTimer()
        activeOperation = ""
        sampleStepIndex += 1
        Qt.callLater(runNextSampleStep)
    }

    function runSampleClaim() {
        if (sampleRunning) return false
        sampleStatus = "Loading sample data"
        sampleError = ""
        sampleDetail = ""
        sampleStepIndex = 0
        samplePendingJobId = ""
        samplePendingMarker = ""
        samplePendingOperation = ""
        lastProofPath = ""
        lastProofDurationSeconds = 0
        lastClaimTxId = ""
        lastTokenSettlementTxId = ""
        lastClaimAmount = ""

        var configError = testnetConfigurationError()
        if (configError !== "") {
            sampleStatus = "Claim failed"
            sampleError = configError
            maybeFinishAutoRunSample()
            return false
        }

        sampleRunning = true
        sampleSteps = [
            ["startSampleFixture", [distributionStateDir], "SAMPLE_FIXTURE_OK", "Loading sample data", "sampleFixture"],
            ["startInitDistribution", [distributionStateDir + "/eligible.csv", distributorAccount, tokenId, tokenSourceAccount, testnetRpc, expiryUnix, recoveryAddress], "INIT_OK", "Eligibility list ready", "initDistribution"],
            ["startFund", [airdropName, fundAmount], "FUND_OK", "Distribution pool funded", "fund"],
            ["startCheckEligibility", [airdropName, distributionStateDir + "/bundle.json", distributionStateDir + "/wallet.seed", distributionStateDir + "/shielded_destination.json"], "ELIGIBILITY_OK", "Checking claim eligibility", "checkEligibility"],
            ["startProve", [airdropName, distributionStateDir + "/bundle.json", distributionStateDir + "/wallet.seed", distributionStateDir + "/shielded_destination.json"], "PROVE_LOCAL_OK", "Generating your private proof", "prove"],
            ["startVerify", [airdropName, distributionStateDir + "/proof.json"], "VERIFY_OK", "Proof verified", "verify"],
            ["startClaim", [airdropName, distributionStateDir + "/proof.json", relayerUrl, serializedLezTxPath], "CLAIM_OK", "Submitting claim", "claim"]
        ]
        Qt.callLater(runNextSampleStep)
        return true
    }

    function claimCurrentDistribution() {
        if (sampleRunning) return false
        sampleStatus = "Checking claim eligibility"
        sampleError = ""
        sampleDetail = ""
        sampleStepIndex = 0
        samplePendingJobId = ""
        samplePendingMarker = ""
        samplePendingOperation = ""
        lastProofPath = ""
        lastProofDurationSeconds = 0
        lastClaimTxId = ""
        lastTokenSettlementTxId = ""
        lastClaimAmount = ""

        var configError = claimConfigurationError()
        if (configError !== "") {
            sampleStatus = "Claim failed"
            sampleError = configError
            return false
        }

        if (!loadDestinationPacket(destinationPacket)) {
            sampleStatus = "Claim failed"
            return false
        }

        var airdrop = claimAirdropName()
        sampleRunning = true
        sampleSteps = [
            ["startCheckEligibility", [airdrop, claimBundlePath(), distributionStateDir + "/wallet.seed", destinationPacket], "ELIGIBILITY_OK", "Checking claim eligibility", "checkEligibility"],
            ["startProve", [airdrop, claimBundlePath(), distributionStateDir + "/wallet.seed", destinationPacket], "PROVE_LOCAL_OK", "Generating your private proof", "prove"],
            ["startVerify", [airdrop, distributionStateDir + "/proof.json"], "VERIFY_OK", "Proof verified", "verify"],
            ["startClaim", [airdrop, distributionStateDir + "/proof.json", relayerUrl, serializedLezTxPath], "CLAIM_OK", "Submitting claim", "claim"]
        ]
        Qt.callLater(runNextSampleStep)
        return true
    }

    function submitClaimAnyway() {
        if (!claimAlreadyClaimed() || duplicateClaimRunning || sampleRunning) return false
        if (serializedLezTxPath === "") {
            duplicateClaimStatus = "Claim transaction file is not configured."
            return false
        }

        duplicateClaimStatus = "Submitting the same claim again..."
        var response = callClient("startClaim", [
            claimAirdropName(),
            distributionStateDir + "/proof.json",
            relayerUrl,
            serializedLezTxPath
        ])
        var parsed = parseClientJson(response)
        if (!responseHas(response, "JOB_STARTED") || !parsed || !parsed.job_id) {
            duplicateClaimStatus = friendlyError(response)
            console.warn("DISTRIBUTIONX_DUPLICATE_CLAIM_ERROR", String(response))
            return false
        }

        duplicateClaimJobId = String(parsed.job_id)
        duplicateClaimRunning = true
        console.log("DISTRIBUTIONX_DUPLICATE_CLAIM_ATTEMPT")
        duplicateClaimJobTimer.restart()
        return true
    }

    function pollDuplicateClaimJob() {
        if (!duplicateClaimRunning || duplicateClaimJobId === "") {
            duplicateClaimJobTimer.stop()
            return
        }

        var response = callClient("jobStatus", [duplicateClaimJobId])
        if (responseHas(response, "JOB_RUNNING")) return

        duplicateClaimJobTimer.stop()
        var parsed = parseClientJson(response)
        var output = parsed && parsed.output !== undefined ? String(parsed.output) : String(response)
        duplicateClaimJobId = ""
        duplicateClaimRunning = false

        if (responseHas(output, "E_ALREADY_CLAIMED")) {
            duplicateClaimStatus = "E_ALREADY_CLAIMED · duplicate rejected"
            console.warn("DISTRIBUTIONX_DUPLICATE_CLAIM_REJECTED E_ALREADY_CLAIMED")
            return
        }
        if (responseHas(output, "CLAIM_OK")) {
            duplicateClaimStatus = "Unexpected: duplicate claim was accepted."
            console.error("DISTRIBUTIONX_DUPLICATE_CLAIM_UNEXPECTEDLY_ACCEPTED")
            return
        }

        duplicateClaimStatus = friendlyError(output)
        console.warn("DISTRIBUTIONX_DUPLICATE_CLAIM_ERROR", output)
    }

    Component.onCompleted: {
        configureFromArguments()
        Qt.callLater(refreshAirdropsUntilReady)
        // Developer/CI auto-run is gated behind dev UI.
        if (Qt.application.arguments.indexOf("distributionx-auto-run-sample") !== -1) {
            if (!devUiEnabled) {
                console.log("DISTRIBUTIONX_AUTO_RUN_SAMPLE_REFUSED",
                    "distributionx-dev-ui=1 required to enable auto-run-sample; ignoring")
            } else {
                screen = "sample"
                autoQuitAfterSample = Qt.application.arguments.indexOf("distributionx-auto-quit") !== -1
                Qt.callLater(function() {
                    runSampleClaim()
                })
            }
        }
    }

    Timer {
        id: sampleJobTimer
        interval: 1000
        repeat: true
        onTriggered: root.pollSampleJob()
    }

    Timer {
        id: duplicateClaimJobTimer
        interval: 250
        repeat: true
        onTriggered: root.pollDuplicateClaimJob()
    }

    Timer {
        id: csvValidationTimer
        interval: 250
        repeat: true
        onTriggered: root.pollCsvValidationJob()
    }

    Timer {
        id: actionJobTimer
        interval: 250
        repeat: true
        onTriggered: root.pollActionJob()
    }

    Timer {
        id: proofTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.proofStartedAtMs > 0) {
                root.proofElapsedSeconds = Math.floor((Date.now() - root.proofStartedAtMs) / 1000)
            }
        }
    }

    Timer {
        id: registryRefreshTimer
        interval: 750
        repeat: true
        onTriggered: {
            root.registryRefreshAttempts += 1
            if (root.refreshAirdrops() || root.registryRefreshAttempts >= 20) {
                stop()
            }
        }
    }

    Timer {
        id: claimPageRefreshTimer
        interval: 500
        repeat: false
        onTriggered: {
            var ok = root.refreshClaimPage()
            var recoverable = root.claimantTokenBalanceError.indexOf("client module is not loaded") !== -1
                || root.claimantTokenBalanceError.indexOf("Invalid response") !== -1
                || root.claimantTokenBalanceError.indexOf("local DistributionX helper") !== -1
            if (!ok && recoverable && root.screen === "claim" && !root.sampleRunning && root.claimPageRefreshAttempts < 90) {
                root.claimPageRefreshAttempts += 1
                interval = 1000
                restart()
                return
            }
            root.claimPageRefreshAttempts = 0
            interval = 500
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.theme.bg
    }

    PaperGrain {
        anchors.fill: parent
        theme: root.theme
        z: 1
    }

    Loader {
        id: screenLoader
        anchors.fill: parent
        z: 2
        source: root.screen === "landing" ? "screens/Landing.qml" :
                root.screen === "sample" ? "screens/SampleRun.qml" :
                root.screen === "distributor" ? "screens/DistributorWizard.qml" :
                root.screen === "claim" ? "screens/ClaimScreen.qml" :
                "screens/MonitorScreen.qml"
        onLoaded: {
            if (item && item.hasOwnProperty("appRoot")) {
                item.appRoot = root
            }
            if (root.screen === "claim") {
                root.scheduleClaimPageRefresh()
            }
        }
    }
}
