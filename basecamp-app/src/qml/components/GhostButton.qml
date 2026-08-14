import QtQuick
import QtQuick.Controls

Button {
    id: root
    property var theme
    property bool busy: false
    property string busyText: ""
    property string iconSource: ""
    property int paddingH: 14

    height: 36
    leftPadding: paddingH
    rightPadding: paddingH

    background: Rectangle {
        color: root.hovered && root.theme ? root.theme.surfaceSubtle : "transparent"
        radius: root.theme ? root.theme.rMd : 10
        border.width: 1
        border.color: root.theme ? root.theme.lineStrong : "#1F2937"
        opacity: root.enabled || root.busy ? 1.0 : 0.45
    }

    contentItem: Item {
        implicitWidth: buttonContent.implicitWidth
        implicitHeight: buttonContent.implicitHeight
        Row {
            id: buttonContent
            anchors.centerIn: parent
            spacing: 7
            BusyIndicator {
                width: 14
                height: 14
                visible: root.busy
                running: root.visible && root.busy
            }
            Image {
                width: 16
                height: 16
                visible: !root.busy && root.iconSource.length > 0
                source: root.iconSource
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
            Text {
                text: root.busy && root.busyText.length > 0 ? root.busyText : root.text
                color: root.theme ? root.theme.fg : "#0F172A"
                font.family: root.theme ? root.theme.fontBody : "sans-serif"
                font.pixelSize: 13
                font.weight: Font.Medium
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }

    scale: pressed ? 0.97 : 1.0
    Behavior on scale {
        NumberAnimation { duration: root.theme ? root.theme.durFast : 120; easing.type: Easing.OutCubic }
    }
}
