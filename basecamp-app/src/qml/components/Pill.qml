import QtQuick

Rectangle {
    id: root
    property var theme
    property string text: ""
    property string tone: "neutral" // "neutral" | "accent" | "danger" | "success"
    property bool pulsing: false

    readonly property color toneColor: theme
        ? (tone === "accent"  ? theme.accent
        :  tone === "danger"  ? theme.danger
        :  tone === "success" ? theme.success
        :                       theme.fg2)
        : "#475569"

    implicitWidth: row.implicitWidth + 20
    implicitHeight: 22
    radius: 11
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(toneColor.r, toneColor.g, toneColor.b, 0.32)

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Rectangle {
            id: dot
            visible: root.pulsing
            width: 7; height: 7; radius: 4
            color: root.toneColor
            anchors.verticalCenter: parent.verticalCenter
            SequentialAnimation on scale {
                running: dot.visible && root.pulsing
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 1.4; duration: 800; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 1.4; to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
            }
        }

        Text {
            text: root.text
            color: root.toneColor
            font.family: root.theme ? root.theme.fontBody : "sans-serif"
            font.pixelSize: 11
            font.letterSpacing: 0.4
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
