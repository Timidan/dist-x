import QtQuick

Rectangle {
    id: root
    property var theme
    property string label: ""
    property string value: ""
    property string sub: ""
    default property alias content: extra.data

    color: theme ? theme.surface : "#FFFFFF"
    border.color: theme ? theme.line : "#1F293714"
    border.width: 1
    radius: theme ? theme.rLg : 14

    implicitHeight: layoutCol.implicitHeight + 36

    Column {
        id: layoutCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 18
        spacing: 8

        Text {
            visible: root.label.length > 0
            text: root.label
            color: root.theme ? root.theme.fg3 : "#94A3B8"
            font.pixelSize: 11
            font.letterSpacing: 1.6
            font.capitalization: Font.AllUppercase
            font.family: root.theme ? root.theme.fontMono : "monospace"
            width: parent.width
            elide: Text.ElideRight
        }
        Text {
            visible: root.value.length > 0
            text: root.value
            color: root.theme ? root.theme.fg : "#0F172A"
            font.family: root.theme ? root.theme.fontDisplay : "sans-serif"
            font.pixelSize: 28
            font.weight: Font.DemiBold
            font.letterSpacing: -0.4
            width: parent.width
            elide: Text.ElideMiddle
        }
        Text {
            visible: root.sub.length > 0
            text: root.sub
            color: root.theme ? root.theme.fg3 : "#94A3B8"
            font.pixelSize: 11
            font.family: root.theme ? root.theme.fontMono : "monospace"
            width: parent.width
            elide: Text.ElideRight
        }
        Item {
            id: extra
            width: parent.width
            implicitHeight: childrenRect.height
            height: implicitHeight
        }
    }
}
