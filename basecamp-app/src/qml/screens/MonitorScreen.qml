import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: page
    property var appRoot
    readonly property var currentAirdrop: appRoot && (appRoot.airdrops.length >= 0 || appRoot.selectedAirdropId !== "")
        ? appRoot.selectedAirdrop()
        : null
    readonly property int totalFunded: currentAirdrop ? Number(currentAirdrop.total_funded) : 0
    readonly property int totalClaimed: currentAirdrop ? Number(currentAirdrop.total_claimed) : 0
    readonly property int remaining: Math.max(0, totalFunded - totalClaimed)
    readonly property real claimProgress: totalFunded > 0 ? totalClaimed / totalFunded : 0

    function shortHex(value) {
        var text = String(value || "")
        if (text.length <= 16) return text
        return text.substring(0, 8) + "..." + text.substring(text.length - 8)
    }

    Topbar {
        id: topbar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        theme: page.appRoot ? page.appRoot.theme : null
        folio: "DistributionX · Registry"
        backVisible: true
        onBackClicked: if (appRoot) appRoot.screen = "landing"

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: page.currentAirdrop ? page.currentAirdrop.status : "no distribution selected"
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
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    text: "DISTRIBUTION"
                    color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                    font.pixelSize: 11
                    font.letterSpacing: 1.6
                    font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                }
                Text {
                    Layout.fillWidth: true
                    text: page.currentAirdrop ? page.currentAirdrop.name : "No distributions"
                    color: appRoot ? appRoot.theme.fg : "#0F172A"
                    font.family: appRoot ? appRoot.theme.fontDisplay : "sans-serif"
                    font.pixelSize: 26
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }

            GhostButton {
                theme: page.appRoot ? page.appRoot.theme : null
                text: "Refresh"
                onClicked: if (appRoot) appRoot.refreshAirdrops()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            StatTile {
                theme: page.appRoot ? page.appRoot.theme : null
                label: "CLAIMED TOKENS"
                value: page.totalClaimed + " / " + page.totalFunded
                sub: page.currentAirdrop ? page.currentAirdrop.eligible_count + " eligible recipients" : ""
                Layout.fillWidth: true
                Layout.minimumHeight: 170

                ProgressTrack {
                    theme: page.appRoot ? page.appRoot.theme : null
                    width: parent.width
                    indeterminate: false
                    value: page.claimProgress
                }
            }

            StatTile {
                theme: page.appRoot ? page.appRoot.theme : null
                label: "POOL REMAINING"
                value: String(page.remaining)
                sub: page.currentAirdrop ? "token id " + page.shortHex(page.currentAirdrop.token_id) : ""
                Layout.fillWidth: true
                Layout.minimumHeight: 170
            }
        }

        StatTile {
            theme: page.appRoot ? page.appRoot.theme : null
            label: "REGISTRY ENTRY"
            Layout.fillWidth: true
            Layout.minimumHeight: 260

            Column {
                width: parent.width
                spacing: 10

                Repeater {
                    model: page.currentAirdrop ? [
                        { label: "Airdrop id", value: page.currentAirdrop.airdrop_id },
                        { label: "Merkle root", value: page.currentAirdrop.merkle_root },
                        { label: "Distributor", value: page.currentAirdrop.distributor },
                        { label: "Recovery", value: page.currentAirdrop.recovery_address },
                        { label: "State", value: page.currentAirdrop.state_path }
                    ] : []
                    delegate: RowLayout {
                        width: parent.width
                        spacing: 12
                        Text {
                            text: modelData.label
                            color: appRoot ? appRoot.theme.fg3 : "#94A3B8"
                            font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                            font.pixelSize: 11
                            Layout.preferredWidth: 96
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.value
                            color: appRoot ? appRoot.theme.fg : "#0F172A"
                            font.family: appRoot ? appRoot.theme.fontMono : "monospace"
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            GhostButton {
                theme: page.appRoot ? page.appRoot.theme : null
                text: "Close distribution"
                enabled: page.currentAirdrop !== null
                onClicked: {
                    if (appRoot && page.currentAirdrop) {
                        appRoot.callClient("close", [page.currentAirdrop.name])
                        appRoot.refreshAirdrops()
                    }
                }
            }
        }
    }
}
