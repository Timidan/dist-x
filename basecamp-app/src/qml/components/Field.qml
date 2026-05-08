import QtQuick
import QtQuick.Controls

Column {
    id: root
    property var theme
    property string label: ""
    property string placeholder: ""
    property string text: ""
    property string errorText: ""
    property bool mono: true
    property alias inputItem: input
    spacing: 6

    Text {
        text: root.label
        color: root.theme ? root.theme.fg3 : "#94A3B8"
        font.pixelSize: 11
        font.letterSpacing: 1.6
        font.capitalization: Font.AllUppercase
        font.family: root.theme ? root.theme.fontMono : "monospace"
        visible: root.label.length > 0
    }

    Rectangle {
        width: parent.width
        height: 40
        radius: root.theme ? root.theme.rMd : 10
        color: root.theme ? root.theme.surface : "#FFFFFF"
        border.width: 1
        border.color: input.activeFocus
            ? (root.theme ? root.theme.accent : "#1E40AF")
            : (root.errorText.length > 0
                ? (root.theme ? root.theme.danger : "#B91C1C")
                : (root.theme ? root.theme.lineStrong : "#1F293724"))

        TextField {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            text: root.text
            placeholderText: root.placeholder
            placeholderTextColor: root.theme ? root.theme.fg3 : "#94A3B8"
            color: root.theme ? root.theme.fg : "#0F172A"
            font.family: root.mono ? (root.theme ? root.theme.fontMono : "monospace") : "sans-serif"
            font.pixelSize: 12
            background: Rectangle { color: "transparent" }
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            onTextChanged: root.text = text
        }
    }

    Text {
        visible: root.errorText.length > 0
        text: root.errorText
        color: root.theme ? root.theme.danger : "#B91C1C"
        font.pixelSize: 12
    }
}
