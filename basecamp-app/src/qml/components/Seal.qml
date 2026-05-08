import QtQuick

Rectangle {
    id: root
    property var theme
    property string mark: "L"
    property int sizePx: 22

    width: sizePx
    height: sizePx
    radius: sizePx / 2
    color: theme ? theme.accent : "#B0413E"
    border.width: 0

    Text {
        anchors.centerIn: parent
        text: root.mark
        color: root.theme ? root.theme.accentInk : "#FBF8F1"
        font.family: root.theme ? root.theme.fontDisplay : "serif"
        font.italic: true
        font.weight: Font.DemiBold
        font.pixelSize: Math.round(root.sizePx * 0.55)
    }
}
