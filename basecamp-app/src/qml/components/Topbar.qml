import QtQuick

Item {
    id: root
    property var theme
    property string folio: ""
    property string mark: "DistributionX"
    default property alias rightContent: rightSlot.data
    property bool sealVisible: true
    property bool backVisible: false
    signal backClicked()
    height: 44

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: root.theme ? root.theme.line : "#1F293714"
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Rectangle {
            id: backBtn
            visible: root.backVisible
            width: 26; height: 26; radius: 13
            anchors.verticalCenter: parent.verticalCenter
            color: backArea.containsMouse
                ? (root.theme ? root.theme.surfaceSubtle : "#EFE9DD")
                : "transparent"
            border.width: 1
            border.color: backArea.containsMouse
                ? (root.theme ? root.theme.lineStrong : "#1F293724")
                : (root.theme ? root.theme.line : "#1F293714")

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                text: "←"
                color: backArea.containsMouse
                    ? (root.theme ? root.theme.fg : "#1B1612")
                    : (root.theme ? root.theme.fg2 : "#5A5048")
                font.pixelSize: 14
                font.family: root.theme ? root.theme.fontBody : "sans-serif"
            }

            MouseArea {
                id: backArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.backClicked()
            }

            scale: backArea.pressed ? 0.92 : 1.0
            Behavior on scale { NumberAnimation { duration: root.theme ? root.theme.durFast : 120 } }
        }

        Image {
            visible: root.sealVisible
            width: 22
            height: 22
            source: "../assets/icons/distributionx-mark.svg"
            fillMode: Image.PreserveAspectFit
            smooth: true
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.folio
            color: root.theme ? root.theme.fg2 : "#475569"
            font.family: root.theme ? root.theme.fontMono : "monospace"
            font.pixelSize: 11
        }
    }

    Row {
        id: rightSlot
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
    }
}
