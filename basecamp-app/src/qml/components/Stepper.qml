import QtQuick
import QtQuick.Controls

Column {
    id: root
    property var theme
    property var items: []     // array of { label, sublabel, status, progress }
                               // status: "done" | "active" | "upcoming" | "error"
    property string numerals: "arabic"  // "arabic" | "roman"
    spacing: 0

    function _romanize(n) {
        if (n <= 0) return String(n)
        var lookup = ["", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii"]
        return lookup[n] !== undefined ? lookup[n] : String(n)
    }

    Repeater {
        model: root.items
        delegate: Rectangle {
            id: stepDelegate
            width: root.width
            color: "transparent"
            height: contentCol.implicitHeight + 20
            border.width: 0

            // Bottom hairline divider
            Rectangle {
                visible: index < root.items.length - 1
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: root.theme ? root.theme.line : "#1F293714"
            }

            // Connector thread above + below the numeral disc
            Rectangle {
                visible: index > 0
                x: 10
                y: 0
                width: 1
                height: stepDelegate.height / 2 - 11
                color: root.theme ? root.theme.line : "#1F293714"
            }
            Rectangle {
                visible: index < root.items.length - 1
                x: 10
                y: stepDelegate.height / 2 + 11
                width: 1
                height: stepDelegate.height - (stepDelegate.height / 2 + 11)
                color: root.theme ? root.theme.line : "#1F293714"
            }

            Row {
                id: stepRow
                anchors.fill: parent
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                anchors.leftMargin: 0
                anchors.rightMargin: 0
                spacing: 12

                Rectangle {
                    width: 22; height: 22; radius: 11
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.theme ? root.theme.surface : "#FBF8F1"
                    border.width: 1
                    border.color: modelData.status === "active"
                        ? (root.theme ? root.theme.accent : "#1E40AF")
                        : modelData.status === "error"
                        ? (root.theme ? root.theme.danger : "#B91C1C")
                        : (root.theme ? root.theme.lineStrong : "#1F293724")
                    opacity: modelData.status === "done" ? 0.45
                           : modelData.status === "upcoming" ? 0.55
                           : 1.0

                    Text {
                        anchors.centerIn: parent
                        visible: modelData.status !== "done" && modelData.status !== "error"
                        text: root.numerals === "roman" ? root._romanize(index + 1) : String(index + 1)
                        font.pixelSize: root.numerals === "roman" ? 12 : 11
                        font.italic: root.numerals === "roman"
                        font.family: root.numerals === "roman"
                            ? (root.theme ? root.theme.fontDisplay : "serif")
                            : (root.theme ? root.theme.fontMono : "monospace")
                        color: modelData.status === "active"
                            ? (root.theme ? root.theme.accent : "#1E40AF")
                            : modelData.status === "error"
                            ? (root.theme ? root.theme.danger : "#B91C1C")
                            : (root.theme ? root.theme.fg2 : "#475569")
                    }
                    Image {
                        anchors.centerIn: parent
                        visible: modelData.status === "done" || modelData.status === "error"
                        width: 14
                        height: 14
                        source: modelData.status === "done"
                            ? "../assets/icons/check-circle.svg"
                            : "../assets/icons/alert-circle.svg"
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                }

                Column {
                    id: contentCol
                    width: parent.width - 22 - 12 - 36
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        text: modelData.label || ""
                        color: root.theme ? root.theme.fg : "#0F172A"
                        font.family: root.theme ? root.theme.fontBody : "sans-serif"
                        font.pixelSize: 13
                        opacity: modelData.status === "done" ? 0.7
                               : modelData.status === "upcoming" ? 0.55
                               : 1.0
                    }
                    Text {
                        visible: !!modelData.sublabel
                        text: modelData.sublabel || ""
                        color: root.theme ? root.theme.fg3 : "#94A3B8"
                        font.pixelSize: 11
                        font.family: root.theme ? root.theme.fontMono : "monospace"
                    }
                    Loader {
                        active: modelData.progress === true && modelData.status === "active"
                        sourceComponent: ProgressTrack {
                            theme: root.theme
                            indeterminate: true
                            width: contentCol.width
                        }
                    }
                }

                Rectangle {
                    id: pulseDot
                    width: 12; height: 12; radius: 6
                    visible: modelData.status === "active"
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.theme ? root.theme.accent : "#1E40AF"
                    SequentialAnimation on scale {
                        running: pulseDot.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 1.4; duration: 800; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 1.4; to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
                    }
                }
            }
        }
    }
}
