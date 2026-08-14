import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform
import "../components"

Item {
    id: page
    property var appRoot
    property int step: 1

    function stepStatus(i) {
        if (i < step) return "done"
        if (i === step) return "active"
        return "upcoming"
    }

    function shortHex(value) {
        var t = String(value || "")
        if (t.length <= 24) return t
        return t.substring(0, 12) + "…" + t.substring(t.length - 8)
    }

    function applyRpcSuggestion(field, value) {
        if (!value || value.length === 0) return
        field.text = value
        if (appRoot) appRoot.testnetRpc = value
    }

    function canContinue() {
        if (!appRoot) return false
        if (step === 1) return true
        if (step === 2) return appRoot.distributorStatus === "Distribution initialized" && appRoot.lastAirdropId !== ""
        if (step === 3) return appRoot.distributorStatus === "Distribution funded" && appRoot.lastFundedAmount !== ""
        return true
    }

    function hasSufficientDistributorBalance() {
        if (!appRoot) return false
        var amount = Number(appRoot.fundAmount)
        if (isNaN(amount) || amount <= 0) return false
        if (!appRoot.customTokenSettlementConfigured()) return true
        if (appRoot.distributorTokenBalance === "" || appRoot.distributorTokenBalanceError !== "") return false
        var balance = Number(appRoot.distributorTokenBalance)
        return !isNaN(balance) && !isNaN(amount) && amount > 0 && balance >= amount
    }

    function distributorBalanceText() {
        if (!appRoot) return "Token source balance: loading..."
        if (!appRoot.customTokenSettlementConfigured()) return "Native distribution pool funding"
        if (appRoot.distributorTokenBalanceError !== "") return "Token source balance: Error: " + appRoot.distributorTokenBalanceError
        if (appRoot.distributorTokenBalance === "") return "Token source balance: loading..."
        if (appRoot.fundAmount !== "" && !hasSufficientDistributorBalance()) {
            return "Token source balance: " + appRoot.distributorTokenBalance + " tokens - need " + appRoot.fundAmount
        }
        return "Token source balance: " + appRoot.distributorTokenBalance + " tokens"
    }

    function setupBlockingMessage() {
        if (!appRoot || step !== 2) return ""
        if (appRoot.csvValidationRunning) return "Checking CSV"
        if (appRoot.actionRunning) return appRoot.activeOperation
        if (!appRoot.lastCsvInspection || appRoot.lastCsvInspection.status !== "CSV_OK") return ""
        if (appRoot.airdropName === "") return "Distribution name is required before Initialize."
        if (appRoot.distributorAccount === "") return "Signer account is required before Initialize."
        if (appRoot.tokenId === "") return "Token id is required before Initialize."
        if (appRoot.payoutMode === "custom" && appRoot.tokenSourceAccount === "") return "Custom token mode requires a token supply account."
        if (appRoot.testnetRpc === "") return "RPC URL is required before Initialize."
        if (appRoot.recoveryAddress === "") return "Recovery account is required before Initialize."
        return ""
    }

    Connections {
        target: page.appRoot
        ignoreUnknownSignals: true
        function onLastCsvInspectionChanged() {
            var inspection = page.appRoot ? page.appRoot.lastCsvInspection : null
            if (inspection && inspection.total_amount !== undefined && page.appRoot.fundAmount === "3000") {
                page.appRoot.fundAmount = String(inspection.total_amount)
            }
        }
    }

    Topbar {
        id: topbar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        theme: page.appRoot ? page.appRoot.theme : null
        folio: "Setup · No. 0241 · step " + page.step + "/4"
        backVisible: true
        onBackClicked: {
            if (page.step > 1) page.step--
            else if (appRoot) appRoot.screen = "landing"
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: page.step === 1 ? "configure signer"
                : page.step === 2 ? "review list"
                : page.step === 3 ? "fund distribution pool"
                :                   "share claim link"
            color: appRoot ? appRoot.theme.fg2 : "#475569"
            font.family: appRoot ? appRoot.theme.fontMono : "monospace"
            font.pixelSize: 11
        }
    }

    GridLayout {
        anchors.top: topbar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 32
        columns: 2
        columnSpacing: 26
        rowSpacing: 0

        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 240
            spacing: 12

            Text {
                text: "SETUP"
                color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                font.pixelSize: 11
                font.letterSpacing: 1.6
                font.family: appRoot ? appRoot.theme.fontMono : "monospace"
            }

            Stepper {
                theme: page.appRoot ? page.appRoot.theme : null
                numerals: "roman"
                Layout.fillWidth: true
                items: [
                    { label: "Signer",          sublabel: "", status: page.stepStatus(1) },
                    { label: "Recipient list",  sublabel: "", status: page.stepStatus(2) },
                    { label: "Fund pool",       sublabel: "", status: page.stepStatus(3) },
                    { label: "Share claim link", sublabel: "", status: page.stepStatus(4) }
                ]
            }
        }

        ScrollView {
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: parent.width
                spacing: 16

                Text {
                    text: page.step === 1 ? "Distributor signing account"
                        : page.step === 2 ? "Upload the eligibility list"
                        : page.step === 3 ? "Fund the vault"
                        :                   "Publish disclosure"
                    color: appRoot ? appRoot.theme.fg : "#0F172A"
                    font.family: appRoot ? appRoot.theme.fontDisplay : "sans-serif"
                    font.pixelSize: 26
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.4
                }

                Text {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 540
                    wrapMode: Text.WordWrap
                    text: page.step === 1
                        ? "Paste the funded LEZ account that will sign deploy and fund transactions. Claim keys are created or loaded from the claim screen."
                        : page.step === 2
                        ? "Point DistributionX at the recipient CSV and token account. The commitment and encrypted bundle are built locally."
                        : page.step === 3
                        ? "Submit the funding transaction from the distributor account. The vault opens once it is confirmed."
                        : "Disclosure published. Share the claim link with eligible recipients."
                    color: appRoot ? appRoot.theme.fg2 : "#475569"
                    font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
                    font.pixelSize: 14
                    lineHeight: 1.5
                }

                Loader {
                    Layout.fillWidth: true
                    sourceComponent: page.step === 1 ? identityCard
                                  : page.step === 2 ? csvCard
                                  : page.step === 3 ? fundCard
                                  : publishCard
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    GhostButton {
                        theme: page.appRoot ? page.appRoot.theme : null
                        text: "Back"
                        iconSource: "../assets/icons/arrow-left.svg"
                        enabled: page.step > 1
                        onClicked: if (page.step > 1) page.step--
                    }
                    Item { Layout.fillWidth: true }
                    PrimaryButton {
                        theme: page.appRoot ? page.appRoot.theme : null
                        accent: true
                        text: page.step < 4 ? "Continue" : "Open monitor"
                        iconSource: page.step < 4 ? "../assets/icons/arrow-right.svg" : "../assets/icons/document.svg"
                        enabled: page.canContinue()
                        onClicked: {
                            if (page.step < 4) page.step++
                            else if (appRoot) Qt.callLater(function() { appRoot.screen = "monitor" })
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    height: 20
                }
            }
        }
    }

    Component {
        id: identityCard
        StatTile {
            theme: page.appRoot ? page.appRoot.theme : null
            label: "IDENTITY"
            value: appRoot && appRoot.distributorAccount !== "" ? "Connected" : "Not connected"
            sub: "Distributor signing account"
            Column {
                width: parent.width
                spacing: 10
                Field {
                    theme: page.appRoot ? page.appRoot.theme : null
                    width: parent.width
                    label: "Distributor account"
                    placeholder: "Public/..."
                    text: appRoot ? appRoot.distributorAccount : ""
                    onTextChanged: if (appRoot) appRoot.distributorAccount = text
                }
                GhostButton {
                    theme: page.appRoot ? page.appRoot.theme : null
                    text: "Use local signer"
                    iconSource: "../assets/icons/wallet.svg"
                    enabled: appRoot && appRoot.configuredDistributorAccount !== ""
                    onClicked: Qt.callLater(function() { if (appRoot) appRoot.useConfiguredDistributor() })
                }
                Field {
                    id: rpcField
                    theme: page.appRoot ? page.appRoot.theme : null
                    width: parent.width
                    label: "RPC"
                    placeholder: appRoot ? appRoot.localnetRpcSuggestion : "http://127.0.0.1:3040"
                    text: appRoot ? appRoot.testnetRpc : ""
                    onTextChanged: if (appRoot) appRoot.testnetRpc = text
                }
                Text {
                    width: parent.width
                    text: "RPC suggestions"
                    color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                    font.pixelSize: 11
                    font.letterSpacing: 1.6
                    font.capitalization: Font.AllUppercase
                    font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                    elide: Text.ElideRight
                }
                Flow {
                    width: parent.width
                    spacing: 8
                    GhostButton {
                        theme: page.appRoot ? page.appRoot.theme : null
                        paddingH: 10
                        text: "Localnet 127.0.0.1:3040"
                        onClicked: page.applyRpcSuggestion(rpcField, appRoot ? appRoot.localnetRpcSuggestion : "http://127.0.0.1:3040")
                    }
                }
                Rectangle {
                    width: parent.width
                    height: networkContext.implicitHeight + 20
                    radius: appRoot ? appRoot.theme.rMd : 10
                    color: appRoot ? appRoot.theme.surfaceSubtle : "#EFE9DD"
                    border.width: 1
                    border.color: appRoot && appRoot.isLocalRpc() ? appRoot.theme.line : (appRoot ? appRoot.theme.accent : "#9F1239")

                    Column {
                        id: networkContext
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 4

                        Text {
                            width: parent.width
                            text: appRoot ? appRoot.networkContextTitle() : "Network not configured"
                            color: appRoot ? appRoot.theme.fg : "#0F172A"
                            font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: "Changing this URL does not switch the wallet or deployment profile."
                            wrapMode: Text.WordWrap
                            color: appRoot ? appRoot.theme.fg2 : "#475569"
                            font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
                            font.pixelSize: 12
                        }
                    }
                }
                ToastBanner {
                    theme: page.appRoot ? page.appRoot.theme : null
                    width: parent.width
                    tone: appRoot && appRoot.distributorError === "" ? "success" : "error"
                    message: appRoot && appRoot.distributorError !== ""
                        ? appRoot.distributorError
                        : appRoot && appRoot.distributorStatus === "Local signer selected"
                        ? appRoot.distributorStatus
                        : ""
                }
            }
        }
    }
    Component {
        id: csvCard
        StatTile {
            theme: page.appRoot ? page.appRoot.theme : null
            Column {
                width: parent.width
                spacing: 14
                FileDialog {
                    id: eligibilityCsvDialog
                    fileMode: FileDialog.OpenFile
                    nameFilters: ["CSV files (*.csv)", "All files (*)"]
                    onAccepted: {
                        if (appRoot) {
                            appRoot.eligibilityCsvPath = String(file).replace(/^file:\/\//, "")
                            appRoot.lastCsvInspection = null
                            appRoot.csvInspectError = ""
                        }
                    }
                }
                Field {
                    theme: page.appRoot ? page.appRoot.theme : null
                    width: parent.width
                    label: "Distribution name"
                    placeholder: "e.g. juniper-launch"
                    text: appRoot ? appRoot.airdropName : ""
                    mono: false
                    onTextChanged: if (appRoot) appRoot.airdropName = text
                }
                Text {
                    width: parent.width
                    text: "Payout asset"
                    color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                    font.pixelSize: 11
                    font.letterSpacing: 1.6
                    font.capitalization: Font.AllUppercase
                    font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                }
                Flow {
                    width: parent.width
                    spacing: 8
                    GhostButton {
                        theme: page.appRoot ? page.appRoot.theme : null
                        text: "Native LEZ"
                        iconSource: "../assets/icons/native-lez-placeholder.svg"
                        enabled: appRoot && !appRoot.actionRunning && appRoot.payoutMode !== "native"
                        onClicked: Qt.callLater(function() { if (appRoot) appRoot.selectNativePayout() })
                    }
                    GhostButton {
                        theme: page.appRoot ? page.appRoot.theme : null
                        text: "Custom token"
                        iconSource: "../assets/icons/token-stack.svg"
                        enabled: appRoot && !appRoot.actionRunning && appRoot.payoutMode !== "custom"
                        onClicked: Qt.callLater(function() { if (appRoot) appRoot.selectCustomPayout() })
                    }
                }
                Rectangle {
                    width: parent.width
                    height: payoutContext.implicitHeight + 20
                    radius: appRoot ? appRoot.theme.rMd : 10
                    color: appRoot ? appRoot.theme.surfaceSubtle : "#EFE9DD"

                    Column {
                        id: payoutContext
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 4
                        Text {
                            width: parent.width
                            text: appRoot && appRoot.payoutMode === "custom" ? "Custom token settlement" : "Native LEZ payout"
                            color: appRoot ? appRoot.theme.fg : "#0F172A"
                            font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: appRoot && appRoot.payoutMode === "custom"
                                ? "Mint or provide a fungible token supply account for the separate settlement transaction."
                                : "No custom token is minted. DistributionX funds the native LEZ pool."
                            wrapMode: Text.WordWrap
                            color: appRoot ? appRoot.theme.fg2 : "#475569"
                            font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
                            font.pixelSize: 12
                        }
                        Text {
                            width: parent.width
                            visible: appRoot && appRoot.payoutMode === "native"
                            text: appRoot && appRoot.tokenId !== "" ? "Native asset label ready" : "Native asset label required"
                            color: appRoot ? appRoot.theme.fg2 : "#475569"
                            font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                            font.pixelSize: 11
                        }
                        GhostButton {
                            theme: page.appRoot ? page.appRoot.theme : null
                            visible: appRoot && appRoot.payoutMode === "native" && appRoot.tokenId === ""
                            text: "Generate native label"
                            iconSource: "../assets/icons/document.svg"
                            busy: appRoot && appRoot.isOperation("creating native asset label")
                            busyText: "Generating"
                            enabled: appRoot && !appRoot.actionRunning
                            onClicked: Qt.callLater(function() { if (appRoot) appRoot.ensureNativePayoutReady() })
                        }
                    }
                }
                RowLayout {
                    width: parent.width
                    spacing: 10
                    Field {
                        theme: page.appRoot ? page.appRoot.theme : null
                        Layout.fillWidth: true
                        enabled: !(appRoot && appRoot.csvValidationRunning)
                        label: "Eligibility CSV"
                        placeholder: "target/distributionx-testnet/eligible.csv"
                        text: appRoot ? appRoot.eligibilityCsvPath : ""
                        onTextChanged: {
                            if (appRoot) {
                                appRoot.eligibilityCsvPath = text
                                appRoot.lastCsvInspection = null
                                appRoot.csvInspectError = ""
                            }
                        }
                    }
                    GhostButton {
                        theme: page.appRoot ? page.appRoot.theme : null
                        text: "Browse…"
                        iconSource: "../assets/icons/folder.svg"
                        enabled: !(appRoot && appRoot.csvValidationRunning)
                        onClicked: eligibilityCsvDialog.open()
                    }
                }
                RowLayout {
                    width: parent.width
                    spacing: 10
                    visible: appRoot && appRoot.payoutMode === "custom"
                    Field {
                        theme: page.appRoot ? page.appRoot.theme : null
                        Layout.fillWidth: true
                        label: "Token id"
                        placeholder: "Public/..."
                        text: appRoot ? appRoot.tokenId : ""
                        onTextChanged: if (appRoot) appRoot.tokenId = text
                    }
                    GhostButton {
                        theme: page.appRoot ? page.appRoot.theme : null
                        text: "Mint token"
                        iconSource: "../assets/icons/mint.svg"
                        busy: appRoot && appRoot.isOperation("minting token")
                        busyText: "Minting"
                        enabled: appRoot && !appRoot.actionRunning
                        onClicked: Qt.callLater(function() { if (appRoot) appRoot.mintDistributionToken() })
                    }
                }
                Field {
                    theme: page.appRoot ? page.appRoot.theme : null
                    width: parent.width
                    visible: appRoot && appRoot.payoutMode === "custom"
                    label: "Custom-token source account"
                    placeholder: "Public/... supply holding account"
                    text: appRoot ? appRoot.tokenSourceAccount : ""
                    onTextChanged: if (appRoot) appRoot.tokenSourceAccount = text
                }
                Field {
                    theme: page.appRoot ? page.appRoot.theme : null
                    width: parent.width
                    label: "Recovery account"
                    placeholder: "Public/..."
                    text: appRoot ? appRoot.recoveryAddress : ""
                    onTextChanged: if (appRoot) appRoot.recoveryAddress = text
                }
                Flow {
                    width: parent.width
                    spacing: 10
                    GhostButton {
                        theme: page.appRoot ? page.appRoot.theme : null
                        text: "Generate sample CSV"
                        iconSource: "../assets/icons/document.svg"
                        busy: appRoot && appRoot.isOperation("preparing sample csv")
                        busyText: "Generating"
                        enabled: appRoot && !appRoot.actionRunning && !appRoot.csvValidationRunning
                        onClicked: Qt.callLater(function() {
                            if (appRoot) appRoot.prepareSampleFixture()
                        })
                    }
                    GhostButton {
                        theme: page.appRoot ? page.appRoot.theme : null
                        text: "Validate CSV"
                        iconSource: "../assets/icons/check-circle.svg"
                        busy: appRoot && appRoot.csvValidationRunning
                        busyText: "Checking"
                        enabled: appRoot && !appRoot.csvValidationRunning && !appRoot.actionRunning
                        onClicked: Qt.callLater(function() {
                            if (appRoot) appRoot.startCsvValidation(appRoot.eligibilityCsvPath)
                        })
                    }
                    PrimaryButton {
                        theme: page.appRoot ? page.appRoot.theme : null
                        accent: true
                        text: "Initialize"
                        iconSource: "../assets/icons/distribution.svg"
                        busy: appRoot && appRoot.isOperation("initializing the distribution")
                        busyText: "Initializing"
                        enabled: appRoot
                            && appRoot.lastCsvInspection !== null
                            && appRoot.lastCsvInspection.status === "CSV_OK"
                            && appRoot.csvInspectError === ""
                            && !appRoot.actionRunning
                            && !appRoot.csvValidationRunning
                            && appRoot.airdropName !== ""
                            && appRoot.distributorAccount !== ""
                            && appRoot.tokenId !== ""
                            && (appRoot.payoutMode !== "custom" || appRoot.tokenSourceAccount !== "")
                            && appRoot.testnetRpc !== ""
                            && appRoot.recoveryAddress !== ""
                        onClicked: Qt.callLater(function() {
                            if (appRoot) appRoot.initializeDistribution()
                        })
                    }
                }

                ProgressTrack {
                    theme: page.appRoot ? page.appRoot.theme : null
                    width: parent.width
                    visible: appRoot && (appRoot.csvValidationRunning
                        || appRoot.isOperation("preparing sample csv")
                        || appRoot.isOperation("creating token id")
                        || appRoot.isOperation("minting token")
                        || appRoot.isOperation("initializing the distribution"))
                    indeterminate: true
                }

                Rectangle {
                    width: parent.width
                    visible: appRoot && appRoot.lastCsvInspection !== null
                    height: csvPreviewCol.implicitHeight + 16
                    color: appRoot ? appRoot.theme.surfaceSubtle : "#EFE9DD"
                    border.color: appRoot ? appRoot.theme.line : "#E5E7EB"
                    border.width: 1
                    radius: appRoot ? appRoot.theme.rMd : 4

                    Column {
                        id: csvPreviewCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 4
                        Text {
                            text: appRoot && appRoot.lastCsvInspection && appRoot.lastCsvInspection.status === "CSV_OK"
                                ? "CSV looks valid · " + appRoot.lastCsvInspection.row_count + " rows · " + appRoot.lastCsvInspection.total_amount + " tokens · " + (appRoot.lastCsvInspection.bucket_table ? appRoot.lastCsvInspection.bucket_table.length + " bucket(s)" : "0 buckets")
                                : "CSV rejected: " + (appRoot && appRoot.csvInspectError !== "" ? appRoot.csvInspectError : "unknown error")
                            color: appRoot && appRoot.lastCsvInspection && appRoot.lastCsvInspection.status === "CSV_OK"
                                ? appRoot.theme.success
                                : (appRoot ? appRoot.theme.danger : "#9F1239")
                            font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            wrapMode: Text.WordWrap
                            width: parent.width
                        }
                        Repeater {
                            model: appRoot && appRoot.lastCsvInspection && appRoot.lastCsvInspection.preview ? appRoot.lastCsvInspection.preview : []
                            delegate: Text {
                                text: modelData.address_short + "  " + modelData.raw_amount
                                color: appRoot ? appRoot.theme.fg2 : "#475569"
                                font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                                font.pixelSize: 10
                            }
                        }
                    }
                }

                ToastBanner {
                    theme: page.appRoot ? page.appRoot.theme : null
                    width: parent.width
                    tone: appRoot && appRoot.distributorError === "" && page.setupBlockingMessage() === "" ? "success" : "error"
                    message: appRoot && appRoot.distributorError !== ""
                        ? appRoot.distributorError
                        : page.setupBlockingMessage() !== ""
                        ? page.setupBlockingMessage()
                        : appRoot && (appRoot.distributorStatus === "Sample CSV ready" || appRoot.distributorStatus === "Token id ready" || appRoot.distributorStatus === "Token minted" || appRoot.distributorStatus === "Distribution initialized")
                        ? appRoot.distributorStatus
                        : ""
                }
                Rectangle {
                    width: parent.width
                    visible: appRoot && appRoot.lastInitTxId !== ""
                    height: initTxCol.implicitHeight + 16
                    color: appRoot ? appRoot.theme.surfaceSubtle : "#EFE9DD"
                    border.color: appRoot ? appRoot.theme.line : "#E5E7EB"
                    border.width: 1
                    radius: appRoot ? appRoot.theme.rMd : 4

                    Column {
                        id: initTxCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 4
                        Text {
                            text: "Init transaction"
                            color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                            font.pixelSize: 11
                            font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
                        }
                        Text {
                            width: parent.width
                            text: appRoot ? appRoot.lastInitTxId : ""
                            color: appRoot ? appRoot.theme.fg : "#0F172A"
                            font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                            font.pixelSize: 11
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
            }
        }
    }
    Component {
        id: fundCard
        StatTile {
            theme: page.appRoot ? page.appRoot.theme : null
            label: "DISTRIBUTION POOL"
            value: appRoot ? appRoot.fundAmount + " tokens" : "Tokens"
            sub: appRoot ? appRoot.distributorStatus : "Awaiting signed transaction"
            iconSource: "../assets/icons/vault.svg"
            Column {
                width: parent.width
                spacing: 10
                Text {
                    width: parent.width
                    text: page.distributorBalanceText()
                    color: appRoot && appRoot.customTokenSettlementConfigured() && (appRoot.distributorTokenBalanceError !== "" || (appRoot.distributorTokenBalance !== "" && appRoot.fundAmount !== "" && !page.hasSufficientDistributorBalance())) ? appRoot.theme.danger : (appRoot ? appRoot.theme.fg2 : "#475569")
                    font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    text: "Distribution total: " + (appRoot && appRoot.lastCsvInspection ? appRoot.lastCsvInspection.total_amount + " tokens" : "---")
                    color: appRoot ? appRoot.theme.fg2 : "#475569"
                    font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
                Field {
                    theme: page.appRoot ? page.appRoot.theme : null
                    width: parent.width
                    label: "Funding amount"
                    placeholder: "3000"
                    text: appRoot ? appRoot.fundAmount : ""
                    onTextChanged: if (appRoot) appRoot.fundAmount = text
                }
                GhostButton {
                    theme: page.appRoot ? page.appRoot.theme : null
                    text: "Use distribution total"
                    iconSource: "../assets/icons/token-stack.svg"
                    enabled: appRoot && appRoot.lastCsvInspection !== null && !appRoot.actionRunning
                    onClicked: {
                        if (appRoot && appRoot.lastCsvInspection) {
                            appRoot.fundAmount = String(appRoot.lastCsvInspection.total_amount)
                        }
                    }
                }
                PrimaryButton {
                    theme: page.appRoot ? page.appRoot.theme : null
                    accent: true
                    text: "Sign deposit"
                    iconSource: "../assets/icons/vault.svg"
                    busy: appRoot && appRoot.isOperation("funding the distribution")
                    busyText: "Funding"
                    enabled: appRoot
                        && appRoot.distributorStatus === "Distribution initialized"
                        && appRoot.lastAirdropId !== ""
                        && appRoot.fundAmount !== ""
                        && !appRoot.actionRunning
                        && page.hasSufficientDistributorBalance()
                    onClicked: Qt.callLater(function() {
                        if (appRoot) appRoot.fundDistribution()
                    })
                }
                ProgressTrack {
                    theme: page.appRoot ? page.appRoot.theme : null
                    width: parent.width
                    visible: appRoot && appRoot.isOperation("funding the distribution")
                    indeterminate: true
                }
                Rectangle {
                    width: parent.width
                    visible: appRoot && appRoot.lastFundTxId !== ""
                    height: fundTxCol.implicitHeight + 16
                    color: appRoot ? appRoot.theme.surfaceSubtle : "#EFE9DD"
                    border.color: appRoot ? appRoot.theme.line : "#E5E7EB"
                    border.width: 1
                    radius: appRoot ? appRoot.theme.rMd : 4

                    Column {
                        id: fundTxCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 4
                        Text {
                            text: "Fund transaction"
                            color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                            font.pixelSize: 11
                            font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
                        }
                        Text {
                            width: parent.width
                            text: appRoot ? appRoot.lastFundTxId : ""
                            color: appRoot ? appRoot.theme.fg : "#0F172A"
                            font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                            font.pixelSize: 11
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
                ToastBanner {
                    theme: page.appRoot ? page.appRoot.theme : null
                    width: parent.width
                    tone: "error"
                    message: appRoot ? appRoot.distributorError : ""
                }
            }
        }
    }
    Component {
        id: publishCard
        StatTile {
            theme: page.appRoot ? page.appRoot.theme : null
            label: "CLAIM LINK"
            value: "Ready to share"
            sub: appRoot ? appRoot.shareClaimLink() + " · share with eligible recipients" : ""
            iconSource: "../assets/icons/link.svg"
            implicitHeight: 160
        }
    }
}
