import QtQuick
import QtQuick.Controls

Column {
    id: root
    property var theme
    property string label: "SECRET"
    property string placeholder: "Enter secret"
    property bool secretInputMode: true
    property alias inputItem: input
    spacing: 6

    function consumeAndClear() {
        var v = input.text
        input.text = ""
        return v
    }

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
        height: 88
        radius: root.theme ? root.theme.rMd : 10
        color: root.theme ? root.theme.surface : "#FFFFFF"
        border.width: 1
        border.color: input.activeFocus
            ? (root.theme ? root.theme.accent : "#1E40AF")
            : (root.theme ? root.theme.lineStrong : "#1F293724")

        TextArea {
            id: input
            anchors.fill: parent
            anchors.margins: 12
            placeholderText: root.placeholder
            placeholderTextColor: root.theme ? root.theme.fg3 : "#94A3B8"
            color: root.theme ? root.theme.fg : "#0F172A"
            font.family: root.theme ? root.theme.fontMono : "monospace"
            font.pixelSize: 12
            wrapMode: TextEdit.WrapAnywhere
            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
            selectByMouse: true
            background: Rectangle { color: "transparent" }
        }
    }
}
