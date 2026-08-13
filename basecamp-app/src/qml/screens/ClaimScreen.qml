import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform
import "../components"

Item {
    id: page
    property var appRoot
    property bool showClaimLink: false
    readonly property bool alreadyClaimed: appRoot && appRoot.claimAlreadyClaimed()
    readonly property bool claimRejected: appRoot && appRoot.claimEligibilityStatus === "rejected"

    FileDialog {
        id: walletSeedDialog
        fileMode: FileDialog.OpenFile
        nameFilters: ["Seed files (*.seed *.hex *.txt)", "All files (*)"]
        onAccepted: {
            if (appRoot) {
                var path = String(file).replace(/^file:\/\//, "")
                appRoot.importClaimantWallet(path)
            }
        }
    }

    FileDialog {
        id: bundleDialog
        fileMode: FileDialog.OpenFile
        nameFilters: ["Distribution bundles (*.json)", "All files (*)"]
        onAccepted: {
            if (appRoot) {
                var path = String(file).replace(/^file:\/\//, "")
                appRoot.setClaimBundlePath(path)
            }
        }
    }

    Topbar {
        id: topbar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        theme: page.appRoot ? page.appRoot.theme : null
        folio: "Claim"
        backVisible: true
        onBackClicked: if (appRoot) appRoot.screen = "landing"

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: page.alreadyClaimed ? "claimed" : (appRoot ? appRoot.claimEligibilityLabel() : "unchecked")
            color: appRoot ? appRoot.theme.fg2 : "#475569"
            font.family: appRoot ? appRoot.theme.fontMono : "monospace"
            font.pixelSize: 11
        }
    }

    ScrollView {
        anchors.top: topbar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 32
        clip: true
        contentWidth: availableWidth

        RowLayout {
            width: parent.width
            spacing: 28

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: true
                Layout.preferredWidth: 650
                spacing: 18

                Text {
                    text: "Claim tokens"
                    color: appRoot ? appRoot.theme.fg : "#0F172A"
                    font.family: appRoot ? appRoot.theme.fontDisplay : "sans-serif"
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Text {
                            text: "Distribution"
                            color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                            font.pixelSize: 11
                            font.letterSpacing: 1.2
                            font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                            Layout.preferredWidth: 128
                        }
                        Text {
                            Layout.fillWidth: true
                            text: appRoot ? appRoot.claimBundlePath() : ""
                            color: appRoot ? appRoot.theme.fg : "#0F172A"
                            font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                            font.pixelSize: 12
                            elide: Text.ElideMiddle
                        }
                        GhostButton {
                            theme: page.appRoot ? page.appRoot.theme : null
                            text: "Browse"
                            onClicked: bundleDialog.open()
                        }
                        GhostButton {
                            theme: page.appRoot ? page.appRoot.theme : null
                            text: page.showClaimLink ? "Hide link" : "Use link"
                            onClicked: page.showClaimLink = !page.showClaimLink
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: page.showClaimLink
                        Field {
                            id: distributionLink
                            theme: page.appRoot ? page.appRoot.theme : null
                            Layout.fillWidth: true
                            label: "CLAIM LINK"
                            placeholder: "distributionx://claim?id=<airdrop-id>&bundle=<bundle-uri>"
                            text: appRoot ? appRoot.claimLink : ""
                            errorText: appRoot ? appRoot.claimLinkError : ""
                            onTextChanged: if (appRoot) appRoot.claimLink = text
                        }
                        GhostButton {
                            theme: page.appRoot ? page.appRoot.theme : null
                            text: "Load"
                            onClicked: if (appRoot) appRoot.applyClaimLink(distributionLink.text)
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: appRoot ? appRoot.theme.line : "#1F293714" }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Text {
                        text: "Claim key"
                        color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                        font.pixelSize: 11
                        font.letterSpacing: 1.2
                        font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                        Layout.preferredWidth: 128
                    }
                    Text {
                        Layout.fillWidth: true
                        text: appRoot && appRoot.claimantPubkey !== ""
                            ? appRoot.shortPubkey(appRoot.claimantPubkey)
                            : "No seed loaded"
                        color: appRoot && appRoot.claimantPubkey !== ""
                            ? appRoot.theme.fg
                            : (appRoot ? appRoot.theme.fg3 : "#94A3B8")
                        font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                        font.pixelSize: 12
                        elide: Text.ElideMiddle
                    }
                    GhostButton {
                        theme: page.appRoot ? page.appRoot.theme : null
                        text: "Generate key"
                        busy: appRoot && appRoot.isOperation("creating claim key")
                        busyText: "Creating"
                        enabled: appRoot && !appRoot.actionRunning && !appRoot.sampleRunning
                        onClicked: Qt.callLater(function() {
                            if (appRoot) appRoot.createWallet()
                        })
                    }
                    GhostButton {
                        theme: page.appRoot ? page.appRoot.theme : null
                        text: "Browse"
                        onClicked: walletSeedDialog.open()
                    }
                    GhostButton {
                        theme: page.appRoot ? page.appRoot.theme : null
                        text: "Refresh"
                        onClicked: if (appRoot) appRoot.refreshClaimantPubkey()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: appRoot && appRoot.claimantWalletError !== ""
                    text: appRoot ? appRoot.claimantWalletError : ""
                    color: appRoot ? appRoot.theme.danger : "#9F1239"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: appRoot ? appRoot.theme.line : "#1F293714" }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Text {
                            text: "Destination"
                            color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                            font.pixelSize: 11
                            font.letterSpacing: 1.2
                            font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                            Layout.preferredWidth: 128
                        }
                        Field {
                            id: destinationPath
                            theme: page.appRoot ? page.appRoot.theme : null
                            Layout.fillWidth: true
                            label: ""
                            placeholder: "Path to shielded_destination.json"
                            text: appRoot ? appRoot.destinationPacket : ""
                            onTextChanged: if (appRoot && text !== appRoot.destinationPacket) {
                                appRoot.destinationPacket = text
                                appRoot.destinationCommitment = ""
                                appRoot.resetClaimEligibility()
                            }
                        }
                        GhostButton {
                            theme: page.appRoot ? page.appRoot.theme : null
                            text: "Load"
                            onClicked: Qt.callLater(function() {
                                if (appRoot) appRoot.loadDestinationPacket(destinationPath.text)
                            })
                        }
                    }

                    Text {
                        Layout.leftMargin: 140
                        Layout.fillWidth: true
                        visible: appRoot && appRoot.destinationCommitment !== ""
                        text: appRoot ? "Verified " + appRoot.destinationCommitment.substring(0, 16) + "..." : ""
                        color: appRoot ? appRoot.theme.fg2 : "#475569"
                        font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.leftMargin: 140
                        Layout.fillWidth: true
                        visible: appRoot && appRoot.destinationPacket !== ""
                        spacing: 10

                        Text {
                            text: "Balance"
                            color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                            font.pixelSize: 11
                            font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
                            Layout.preferredWidth: 68
                        }
                        Text {
                            Layout.fillWidth: true
                            text: appRoot ? appRoot.claimantBalanceText() : "-"
                            color: appRoot && appRoot.claimantTokenBalanceError !== ""
                                ? appRoot.theme.danger
                                : (appRoot ? appRoot.theme.fg : "#0F172A")
                            font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        GhostButton {
                            theme: page.appRoot ? page.appRoot.theme : null
                            text: "Refresh"
                            enabled: appRoot && !appRoot.sampleRunning
                            onClicked: if (appRoot) appRoot.refreshClaimPage()
                        }
                    }

                    Text {
                        Layout.leftMargin: 140
                        Layout.fillWidth: true
                        visible: appRoot && appRoot.claimantTokenBalanceError !== ""
                        text: appRoot ? appRoot.claimantTokenBalanceError : ""
                        color: appRoot ? appRoot.theme.danger : "#9F1239"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    CheckBox {
                        Layout.leftMargin: 136
                        text: "Recovery material is backed up"
                        checked: appRoot && appRoot.recoveryGateStatus === "attested"
                        onClicked: if (appRoot) {
                            appRoot.recoveryGateStatus = checked ? "attested" : "not-attested"
                            appRoot.backupAttestedAt = checked ? new Date().toISOString() : ""
                            appRoot.resetClaimEligibility()
                            if (checked) Qt.callLater(function() { appRoot.refreshClaimEligibility() })
                        }
                        contentItem: Text {
                            text: parent.text
                            color: appRoot ? appRoot.theme.fg2 : "#475569"
                            font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
                            font.pixelSize: 12
                            leftPadding: parent.indicator ? parent.indicator.width + 8 : 0
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                ToastBanner {
                    theme: page.appRoot ? page.appRoot.theme : null
                    Layout.fillWidth: true
                    tone: page.alreadyClaimed ? "neutral" : "error"
                    message: appRoot ? (appRoot.sampleError !== "" ? appRoot.sampleError : appRoot.claimEligibilityError) : ""
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: appRoot && appRoot.sampleRunning && !appRoot.proofRunning
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: appRoot ? appRoot.sampleStatus : ""
                        color: appRoot ? appRoot.theme.accent : "#B0413E"
                        font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    ProgressTrack {
                        theme: page.appRoot ? page.appRoot.theme : null
                        Layout.fillWidth: true
                        indeterminate: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: appRoot && appRoot.proofRunning
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Preparing private proof"
                            color: appRoot ? appRoot.theme.accent : "#B0413E"
                            font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            Layout.fillWidth: true
                        }
                        Text {
                            text: appRoot ? appRoot.formatElapsed(appRoot.proofElapsedSeconds) : "00:00"
                            color: appRoot ? appRoot.theme.accent : "#B0413E"
                            font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                            font.pixelSize: 13
                        }
                    }
                    ProgressTrack {
                        theme: page.appRoot ? page.appRoot.theme : null
                        Layout.fillWidth: true
                        indeterminate: true
                    }
                }

                StatTile {
                    theme: page.appRoot ? page.appRoot.theme : null
                    label: "DEBUG DETAIL"
                    visible: appRoot && appRoot.debugUiEnabled && appRoot.sampleDetail !== ""
                    Layout.fillWidth: true
                    Layout.minimumHeight: 140

                    ScrollView {
                        width: parent.width
                        height: 140
                        clip: true
                        Text {
                            text: appRoot ? appRoot.sampleDetail : ""
                            color: appRoot ? appRoot.theme.fg2 : "#475569"
                            font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                            font.pixelSize: 10
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
            }

            StatTile {
                id: receiptTile
                theme: page.appRoot ? page.appRoot.theme : null
                label: "STATUS"
                value: appRoot && appRoot.claimEligibilityAmount !== "" ? "+ " + appRoot.claimEligibilityAmount : "-"
                sub: page.alreadyClaimed ? "Already claimed"
                    : appRoot && appRoot.claimEligibilityOk ? "Ready"
                    : appRoot && appRoot.claimEligibilityStatus === "checking" ? "Checking"
                    : page.claimRejected ? "Not claimable"
                    : "Not checked"
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 300
                Layout.minimumHeight: 310

                Loader {
                    active: page.alreadyClaimed
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: 14
                    anchors.topMargin: 14
                    z: 10
                    sourceComponent: PaidStamp {
                        theme: page.appRoot ? page.appRoot.theme : null
                        when: Qt.formatDateTime(new Date(), "dd.MM.yyyy")
                    }
                }

                Column {
                    width: parent.width
                    spacing: 10

                    Rectangle { width: parent.width; height: 1; color: appRoot ? appRoot.theme.line : "#1F293714" }

                    RowLayout {
                        width: parent.width
                        Text { text: "Eligibility"; color: appRoot ? appRoot.theme.fg3 : "#94A3B8"; font.pixelSize: 11; font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"; Layout.fillWidth: true }
                        Text { text: page.alreadyClaimed ? "claimed" : (appRoot ? appRoot.claimEligibilityLabel() : "unchecked")
                               color: page.claimRejected ? (appRoot ? appRoot.theme.danger : "#9F1239") : (appRoot ? appRoot.theme.fg : "#0F172A"); font.pixelSize: 12; font.family: appRoot ? appRoot.theme.fontMono : "monospace" }
                    }
                    RowLayout {
                        width: parent.width
                        visible: appRoot && appRoot.destinationPacket !== ""
                        Text { text: "Balance"; color: appRoot ? appRoot.theme.fg3 : "#94A3B8"; font.pixelSize: 11; font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"; Layout.fillWidth: true }
                        Text { text: appRoot ? appRoot.claimantBalanceText() : "-"
                               color: appRoot && appRoot.claimantTokenBalanceError !== "" ? appRoot.theme.danger : (appRoot ? appRoot.theme.fg : "#0F172A")
                               font.pixelSize: 12; font.family: appRoot ? appRoot.theme.fontMono : "monospace" }
                    }
                    RowLayout {
                        width: parent.width
                        Text { text: "Proof"; color: appRoot ? appRoot.theme.fg3 : "#94A3B8"; font.pixelSize: 11; font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"; Layout.fillWidth: true }
                        Text { text: appRoot && appRoot.proofRunning ? appRoot.formatElapsed(appRoot.proofElapsedSeconds)
                                    : appRoot && (appRoot.sampleStatus === "Proof verified" || appRoot.claimCompleted() || appRoot.lastProofPath !== "") ? "ready"
                                    : "pending"
                               color: appRoot ? appRoot.theme.fg : "#0F172A"; font.pixelSize: 12; font.family: appRoot ? appRoot.theme.fontMono : "monospace" }
                    }
                    RowLayout {
                        width: parent.width
                        visible: appRoot && appRoot.lastClaimTxId !== ""
                        Text { text: "Tx id"; color: appRoot ? appRoot.theme.fg3 : "#94A3B8"; font.pixelSize: 11; font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"; Layout.fillWidth: true }
                        Text { text: appRoot ? String(appRoot.lastClaimTxId).substring(0, 16) + "..." : ""
                               color: appRoot ? appRoot.theme.fg : "#0F172A"; font.pixelSize: 12; font.family: appRoot ? appRoot.theme.fontMono : "monospace"; wrapMode: Text.WrapAnywhere; Layout.maximumWidth: 160 }
                    }
                    RowLayout {
                        width: parent.width
                        visible: page.alreadyClaimed && appRoot && appRoot.lastProofDurationSeconds > 0
                        Text { text: "Proof time"; color: appRoot ? appRoot.theme.fg3 : "#94A3B8"; font.pixelSize: 11; font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"; Layout.fillWidth: true }
                        Pill {
                            theme: page.appRoot ? page.appRoot.theme : null
                            tone: "success"
                            text: appRoot ? appRoot.formatElapsed(appRoot.lastProofDurationSeconds) : "00:00"
                        }
                    }
                    RowLayout {
                        width: parent.width
                        Text { text: "Claim"; color: appRoot ? appRoot.theme.fg3 : "#94A3B8"; font.pixelSize: 11; font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"; Layout.fillWidth: true }
                        Text { text: page.alreadyClaimed ? "Already claimed"
                                    : appRoot && appRoot.sampleError !== "" ? "Needs attention"
                                    : appRoot ? appRoot.sampleStatus : "Ready"
                               color: appRoot && appRoot.sampleError !== "" && !page.alreadyClaimed ? appRoot.theme.danger : (appRoot ? appRoot.theme.fg : "#0F172A")
                               font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
                               font.pixelSize: 12; font.weight: Font.Medium }
                    }

                    Item { width: 1; height: 6 }

                    PrimaryButton {
                        theme: page.appRoot ? page.appRoot.theme : null
                        accent: true
                        text: page.alreadyClaimed ? "Already claimed" : "Claim now"
                        busy: appRoot && appRoot.sampleRunning
                        busyText: appRoot && appRoot.sampleStatus !== "" ? appRoot.sampleStatus : "Claiming"
                        width: parent.width
                        enabled: appRoot && appRoot.canClaim && !page.alreadyClaimed && !page.claimRejected && !appRoot.sampleRunning
                        onClicked: Qt.callLater(function() {
                            if (appRoot) appRoot.claimCurrentDistribution()
                        })
                    }
                }
            }
        }
    }
}
