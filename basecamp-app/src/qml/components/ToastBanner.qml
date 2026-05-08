import QtQuick

Rectangle {
    id: root
    property var theme
    property string message: ""
    property string tone: "error"   // "error" | "success" | "neutral"

    readonly property color bgColor: theme
        ? (tone === "error"   ? theme.dangerSoft
        :  tone === "success" ? Qt.rgba(21/255, 128/255, 61/255, 0.08)
        :                       theme.surfaceSubtle)
        : "#FEF2F2"
    readonly property color borderColor: theme
        ? (tone === "error"   ? Qt.rgba(220/255, 38/255, 38/255, 0.18)
        :  tone === "success" ? Qt.rgba(21/255, 128/255, 61/255, 0.20)
        :                       theme.line)
        : "#FCA5A5"
    readonly property color fgColor: theme
        ? (tone === "error"   ? theme.danger
        :  tone === "success" ? theme.success
        :                       theme.fg2)
        : "#7F1D1D"

    visible: message.length > 0
    color: bgColor
    border.color: borderColor
    border.width: 1
    radius: theme ? theme.rMd : 10
    height: visible ? 44 : 0
    Behavior on opacity { NumberAnimation { duration: theme ? theme.durBase : 220 } }

    Text {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        text: root.message
        color: root.fgColor
        font.family: root.theme ? root.theme.fontBody : "sans-serif"
        font.pixelSize: 12
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
    }
}
