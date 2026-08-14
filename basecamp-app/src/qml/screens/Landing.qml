import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: landing
    property var appRoot

    Rectangle {
        anchors.fill: parent
        color: appRoot ? appRoot.theme.bg : "#FAFAF9"
    }

    Topbar {
        id: topbar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        theme: landing.appRoot ? landing.appRoot.theme : null
        folio: "DistributionX · Private Distribution 0241/2026"

        Pill {
            anchors.verticalCenter: parent.verticalCenter
            theme: landing.appRoot ? landing.appRoot.theme : null
            text: appRoot ? appRoot.networkModeLabel() : "RPC missing"
            tone: appRoot && appRoot.testnetRpc !== "" ? (appRoot.isLocalRpc() ? "neutral" : "accent") : "danger"
            pulsing: appRoot && appRoot.testnetRpc === ""
        }

        Pill {
            anchors.verticalCenter: parent.verticalCenter
            theme: landing.appRoot ? landing.appRoot.theme : null
            text: appRoot && appRoot.distributorAccount !== ""
                ? appRoot.shortPubkey(appRoot.distributorAccount)
                : "no account"
            tone: appRoot && appRoot.distributorAccount !== "" ? "accent" : "neutral"
        }

        Rectangle {
            id: statusDot
            width: 7; height: 7; radius: 4
            anchors.verticalCenter: parent.verticalCenter
            color: appRoot && appRoot.hasBridge() ? appRoot.theme.accent : (appRoot ? appRoot.theme.fg3 : "#94A3B8")
            SequentialAnimation on scale {
                running: appRoot && appRoot.hasBridge()
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 1.4; duration: 800 }
                NumberAnimation { from: 1.4; to: 1.0; duration: 800 }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: appRoot && appRoot.hasBridge() ? "client connected" : "bridge offline"
            color: appRoot ? appRoot.theme.fg2 : "#475569"
            font.family: appRoot ? appRoot.theme.fontMono : "monospace"
            font.pixelSize: 11
        }
    }

    // Body
    GridLayout {
        anchors.top: topbar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 32
        columns: 2
        columnSpacing: 32
        rowSpacing: 0

        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
            Layout.preferredWidth: 600
            spacing: 16

            Pill {
                theme: landing.appRoot ? landing.appRoot.theme : null
                text: "PRIVATE / ALLOWLIST"
                tone: "accent"
                pulsing: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Image {
                    width: 30
                    height: 30
                    source: "../assets/icons/distributionx-mark.svg"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                Text {
                    Layout.fillWidth: true
                    text: "DistributionX"
                    color: appRoot ? appRoot.theme.fg : "#0F172A"
                    font.family: appRoot ? appRoot.theme.fontDisplay : "serif"
                    font.pixelSize: 40
                    font.weight: Font.DemiBold
                    font.italic: true
                    font.letterSpacing: -0.4
                    wrapMode: Text.WordWrap
                    lineHeight: 1.0
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.maximumWidth: 540
                text: "Distributors create private allowlist drops. Recipients claim from a shared link without revealing which wallet they hold."
                color: appRoot ? appRoot.theme.fg2 : "#475569"
                font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
                font.pixelSize: 14
                wrapMode: Text.WordWrap
                lineHeight: 1.5
            }

            // Normal-mode primary actions — role-tagged
            RowLayout {
                Layout.topMargin: 12
                spacing: 16

                ColumnLayout {
                    spacing: 4
                    Text {
                        text: "DISTRIBUTOR"
                        color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                        font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                        font.pixelSize: 10
                        font.letterSpacing: 1.4
                    }
                    PrimaryButton {
                        theme: landing.appRoot ? landing.appRoot.theme : null
                        accent: true
                        text: "Create distribution"
                        iconSource: "../assets/icons/distribution.svg"
                        onClicked: if (landing.appRoot) landing.appRoot.screen = "distributor"
                    }
                }

                ColumnLayout {
                    spacing: 4
                    Text {
                        text: "RECIPIENT"
                        color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                        font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                        font.pixelSize: 10
                        font.letterSpacing: 1.4
                    }
                    GhostButton {
                        theme: landing.appRoot ? landing.appRoot.theme : null
                        text: "Claim distribution"
                        iconSource: "../assets/icons/claim.svg"
                        onClicked: if (landing.appRoot) landing.appRoot.screen = "claim"
                    }
                }
            }

            GhostButton {
                Layout.topMargin: 4
                theme: landing.appRoot ? landing.appRoot.theme : null
                text: "View distributions"
                iconSource: "../assets/icons/document.svg"
                onClicked: if (landing.appRoot) landing.appRoot.screen = "monitor"
            }

            RowLayout {
                visible: appRoot && appRoot.devUiEnabled
                Layout.topMargin: 4
                spacing: 12
                Pill {
                    theme: landing.appRoot ? landing.appRoot.theme : null
                    text: "DEV"
                    tone: "danger"
                }
                GhostButton {
                    theme: landing.appRoot ? landing.appRoot.theme : null
                    text: "Try with sample data"
                    iconSource: "../assets/icons/claim.svg"
                    onClicked: if (landing.appRoot) landing.appRoot.screen = "sample"
                }
                GhostButton {
                    theme: landing.appRoot ? landing.appRoot.theme : null
                    text: "Set up real distribution"
                    iconSource: "../assets/icons/distribution.svg"
                    onClicked: if (landing.appRoot) landing.appRoot.screen = "distributor"
                }
            }
        }

        StatTile {
            theme: landing.appRoot ? landing.appRoot.theme : null
            label: "DISTRIBUTIONS"
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 380
            Layout.minimumHeight: 360

            Column {
                width: parent.width
                spacing: 10

                Text {
                    width: parent.width
                    text: appRoot && appRoot.airdrops.length > 0
                        ? appRoot.airdrops.length + " created"
                        : "No distributions"
                    color: appRoot ? appRoot.theme.fg : "#0F172A"
                    font.family: appRoot ? appRoot.theme.fontDisplay : "serif"
                    font.pixelSize: 24
                    font.weight: Font.DemiBold
                }

                GhostButton {
                    theme: landing.appRoot ? landing.appRoot.theme : null
                    text: "Refresh"
                    iconSource: "../assets/icons/refresh.svg"
                    visible: appRoot && appRoot.airdrops.length === 0
                    onClicked: if (appRoot) appRoot.refreshAirdropsUntilReady()
                }

                Repeater {
                    model: appRoot ? appRoot.airdrops : []
                    delegate: Rectangle {
                        width: parent.width
                        height: 72
                        color: "transparent"
                        border.color: appRoot ? appRoot.theme.line : "#E5E7EB"
                        border.width: 1
                        radius: appRoot ? appRoot.theme.rMd : 4

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: appRoot ? appRoot.theme.fg : "#0F172A"
                                    font.family: appRoot ? appRoot.theme.fontBody : "sans-serif"
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: (modelData.airdrop_id ? String(modelData.airdrop_id).substring(0, 8) + "…" : "—") + " · " + (modelData.token_id ? String(modelData.token_id).substring(0, 8) + "…" : "no token")
                                    color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                                    font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.eligible_count + " eligible · " + modelData.total_claimed + "/" + modelData.total_funded + " claimed"
                                    color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                                    font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }

                            ColumnLayout {
                                spacing: 4
                                GhostButton {
                                    theme: landing.appRoot ? landing.appRoot.theme : null
                                    text: "Claim"
                                    iconSource: "../assets/icons/claim.svg"
                                    paddingH: 10
                                    onClicked: {
                                        if (appRoot) {
                                            appRoot.selectRegistryAirdrop(modelData.airdrop_id, modelData.name)
                                            appRoot.screen = "claim"
                                        }
                                    }
                                }
                                GhostButton {
                                    theme: landing.appRoot ? landing.appRoot.theme : null
                                    text: "Monitor"
                                    iconSource: "../assets/icons/document.svg"
                                    paddingH: 10
                                    onClicked: {
                                        if (appRoot) {
                                            appRoot.selectRegistryAirdrop(modelData.airdrop_id, modelData.name)
                                            appRoot.screen = "monitor"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

            }
        }
    }
}
