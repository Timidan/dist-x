import QtQuick

Rectangle {
    id: root
    property var theme
    property real shimmerOpacity: 0.55
    height: 10
    radius: 4
    color: Qt.rgba(0, 0, 0, 0.06)
    clip: true

    Rectangle {
        id: glow
        height: parent.height
        width: parent.width * 0.4
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, root.shimmerOpacity) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.0) }
        }
        NumberAnimation on x {
            running: root.visible
            loops: Animation.Infinite
            from: -glow.width
            to: root.width
            duration: 1600
            easing.type: Easing.InOutQuad
        }
    }
}
