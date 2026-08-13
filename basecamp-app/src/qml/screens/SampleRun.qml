import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: page
    property var appRoot
    property string badge: "Sample mode • test data only"

    function statusToItems(status, error) {
        var elapsed = appRoot ? appRoot.formatElapsed(appRoot.proofElapsedSeconds) : "00:00"
        var proveSub = appRoot && appRoot.proofRunning
            ? elapsed + " elapsed · Real proof generation can take several minutes. You can leave this window open."
            : (appRoot && appRoot.lastProofDurationSeconds > 0 ? "Proof generated in " + appRoot.formatElapsed(appRoot.lastProofDurationSeconds)
                : (appRoot && appRoot.lastProofPath !== "" ? "Proof ready" : "privacy proof"))
        var deliverSub = appRoot && appRoot.sampleStatus === "Submitting claim" ? "submitting claim"
            : appRoot && appRoot.lastClaimTxId !== "" ? "tx " + String(appRoot.lastClaimTxId).substring(0, 12) + "…" : ""
        var completionLabel = appRoot ? appRoot.claimCompletionStatus() : "Native payout confirmed"
        var rowDefs = [
            { label: "Loading sample data",             sub: appRoot ? appRoot.distributionStateDir : "target/distributionx-testnet" },
            { label: "Eligibility list ready",          sub: appRoot && appRoot.lastEligibleCount > 0 ? appRoot.lastEligibleCount + " entries" : "8 entries" },
            { label: "Distribution pool funded",        sub: appRoot ? appRoot.fundAmount + " tokens" : "tokens" },
            { label: "Generating your private proof",   sub: proveSub },
            { label: "Proof verified",                  sub: "checked locally" },
            { label: completionLabel,                    sub: deliverSub }
        ]
        var stages = ["Loading sample data", "Eligibility list ready", "Distribution pool funded",
                      "Generating your private proof", "Proof verified", completionLabel]
        var activeStatus = status === "Submitting claim" ? completionLabel : status
        var activeIdx = stages.indexOf(activeStatus)
        if (status === "Ready to claim") activeIdx = -1
        var failed = (status === "Claim failed") || (error && error.length > 0)
        var items = []
        for (var i = 0; i < rowDefs.length; i++) {
            var s = "upcoming"
            if (appRoot && appRoot.claimCompleted()) s = "done"
            else if (failed && i === Math.max(0, activeIdx)) s = "error"
            else if (activeIdx === -1) s = "upcoming"
            else if (i < activeIdx) s = "done"
            else if (i === activeIdx) s = "active"
            items.push({
                label: rowDefs[i].label,
                sublabel: rowDefs[i].sub,
                status: s,
                progress: (s === "active" && rowDefs[i].label === "Generating your private proof")
            })
        }
        return items
    }

    Topbar {
        id: topbar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        theme: page.appRoot ? page.appRoot.theme : null
        folio: "DistributionX · Sample"
        backVisible: true
        onBackClicked: if (appRoot) appRoot.screen = "landing"

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: appRoot && appRoot.sampleStatus !== "Ready to claim"
                  ? appRoot.sampleStatus.toLowerCase()
                  : "ready to claim"
            color: appRoot ? appRoot.theme.fg2 : "#475569"
            font.family: appRoot ? appRoot.theme.fontMono : "monospace"
            font.pixelSize: 11
        }
    }

    ColumnLayout {
        anchors.top: topbar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 32
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    text: page.badge
                    color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                    font.pixelSize: 11
                    font.letterSpacing: 1.6
                    font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                }
                Text {
                    text: "DistributionX Sample Run"
                    color: appRoot ? appRoot.theme.fg : "#0F172A"
                    font.family: appRoot ? appRoot.theme.fontDisplay : "sans-serif"
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.4
                }
                Text {
                    text: "Shielded destination: " + (appRoot ? appRoot.destinationPacket : "")
                    color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                    font.pixelSize: 11
                    font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                }
            }
            Pill {
                theme: page.appRoot ? page.appRoot.theme : null
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                text: appRoot ? (
                    appRoot.sampleStatus === "Ready to claim" ? "ready"
                    : appRoot.claimCompleted() ? "done"
                    : appRoot.sampleError !== "" ? "error"
                    : "running"
                ) : "ready"
                tone: appRoot && appRoot.sampleError !== "" ? "danger"
                    : appRoot && appRoot.claimCompleted() ? "success"
                    : "accent"
                pulsing: appRoot && appRoot.sampleStatus !== "Ready to claim"
                       && !appRoot.claimCompleted()
                       && appRoot.sampleError === ""
            }
        }

        RowLayout {
            spacing: 12
            PrimaryButton {
                theme: page.appRoot ? page.appRoot.theme : null
                accent: true
                text: "Run sample claim"
                busy: appRoot && appRoot.sampleRunning
                busyText: appRoot && appRoot.sampleStatus !== "" ? appRoot.sampleStatus : "Running"
                enabled: appRoot && appRoot.canClaim && !appRoot.sampleRunning
                onClicked: Qt.callLater(function() {
                    if (appRoot) appRoot.runSampleClaim()
                })
            }
            GhostButton {
                theme: page.appRoot ? page.appRoot.theme : null
                text: "Open claim screen"
                onClicked: if (appRoot) appRoot.screen = "claim"
            }
        }

        StatTile {
            theme: page.appRoot ? page.appRoot.theme : null
            Layout.fillWidth: true
            Layout.minimumHeight: 380

            Stepper {
                theme: page.appRoot ? page.appRoot.theme : null
                numerals: "roman"
                width: parent.width
                items: page.statusToItems(
                    appRoot ? appRoot.sampleStatus : "Ready to claim",
                    appRoot ? appRoot.sampleError : ""
                )
            }
        }

        ToastBanner {
            theme: page.appRoot ? page.appRoot.theme : null
            Layout.fillWidth: true
            tone: "error"
            message: appRoot ? appRoot.sampleError : ""
        }

        Text {
            visible: appRoot && appRoot.claimCompleted()
            text: appRoot && appRoot.customTokenSettlementConfirmed()
                ? "Custom-token settlement confirmed by a separate included transaction."
                : "Native payout confirmed in the included claim transaction."
            color: appRoot ? appRoot.theme.success : "#15803D"
            font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        // Post-action receipt
        StatTile {
            theme: page.appRoot ? page.appRoot.theme : null
            label: "RECEIPT"
            visible: appRoot && (appRoot.lastAirdropId !== "" || appRoot.lastClaimTxId !== "")
            Layout.fillWidth: true
            Layout.minimumHeight: 140

            Column {
                width: parent.width
                spacing: 6
                Repeater {
                    model: [
                        { label: "Airdrop id",  value: appRoot ? appRoot.lastAirdropId : "" },
                        { label: "Bundle path", value: appRoot ? appRoot.lastBundlePath : "" },
                        { label: "Eligible",    value: appRoot && appRoot.lastEligibleCount > 0 ? String(appRoot.lastEligibleCount) : "" },
                        { label: "Funded",      value: appRoot && appRoot.lastTotalFunded > 0 ? String(appRoot.lastTotalFunded) : "" },
                        { label: "Claim tx",    value: appRoot ? appRoot.lastClaimTxId : "" },
                        { label: "Proof time",  value: appRoot && appRoot.lastProofDurationSeconds > 0 ? appRoot.formatElapsed(appRoot.lastProofDurationSeconds) : "" },
                        { label: "Amount",      value: appRoot ? appRoot.lastClaimAmount : "" }
                    ]
                    delegate: RowLayout {
                        width: parent.width
                        spacing: 12
                        visible: modelData.value !== ""
                        Text {
                            text: modelData.label
                            color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                            font.pixelSize: 11
                            font.letterSpacing: 1.0
                            font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                            Layout.preferredWidth: 96
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.value
                            color: appRoot ? appRoot.theme.fg : "#0F172A"
                            font.pixelSize: 12
                            font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                            elide: Text.ElideMiddle
                        }
                    }
                }
            }
        }

        // Raw debug detail (only when --distributionx-debug-ui=1)
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

        Item { Layout.fillHeight: true }
    }
}
