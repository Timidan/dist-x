import QtQuick

Rectangle {
    id: root
    property var theme
    property bool indeterminate: true
    property real value: 0   // 0.0 - 1.0

    height: 4
    radius: 2
    color: theme ? Qt.rgba(0, 0, 0, 0.08) : "#1F293714"
    clip: true

    Rectangle {
        id: bar
        height: parent.height
        radius: parent.radius
        color: root.theme ? root.theme.accent : "#1E40AF"
        width: root.indeterminate ? root.width * 0.30 : root.width * Math.max(0, Math.min(1, root.value))
        x: 0

        NumberAnimation on x {
            running: root.visible && root.indeterminate
            loops: Animation.Infinite
            from: -root.width * 0.30
            to: root.width
            duration: 1400
            easing.type: Easing.InOutQuad
        }
    }
}
