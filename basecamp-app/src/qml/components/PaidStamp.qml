import QtQuick

Item {
    id: root
    property var theme
    property string when: ""
    property real angle: -8

    width: 138
    height: 64

    Rectangle {
        id: frame
        anchors.fill: parent
        color: "transparent"
        border.width: 2
        border.color: root.theme ? root.theme.accent : "#B0413E"
        radius: 4
        rotation: root.angle
        opacity: 0.78

        Column {
            anchors.centerIn: parent
            spacing: 1
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "PAID"
                color: root.theme ? root.theme.accent : "#B0413E"
                font.family: root.theme ? root.theme.fontDisplay : "serif"
                font.weight: Font.Bold
                font.pixelSize: 30
                font.italic: true
                font.letterSpacing: 4
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.when
                color: root.theme ? root.theme.accent : "#B0413E"
                font.family: root.theme ? root.theme.fontMono : "monospace"
                font.pixelSize: 9
                font.letterSpacing: 2
                opacity: 0.85
            }
        }
    }

    // mount-in animation: scale + opacity overshoot
    Component.onCompleted: {
        frame.scale = 1.4
        frame.opacity = 0
        scaleAnim.start()
        opacityAnim.start()
    }
    NumberAnimation {
        id: scaleAnim
        target: frame
        property: "scale"
        from: 1.4
        to: 1.0
        duration: 320
        easing.type: Easing.OutBack
        easing.overshoot: 2
    }
    NumberAnimation {
        id: opacityAnim
        target: frame
        property: "opacity"
        from: 0
        to: 0.78
        duration: 220
    }
}
