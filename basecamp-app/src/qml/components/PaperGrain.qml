import QtQuick

Canvas {
    id: root
    property var theme
    property real intensity: 0.06        // peak per-dot opacity (0..1)
    property real density: 0.0042         // dots per square pixel (≈4.2k for 1280x820)

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var w = width, h = height
        if (w <= 0 || h <= 0) return
        var inkColor = root.theme ? root.theme.fg : "#1B1612"
        ctx.fillStyle = inkColor

        var count = Math.round(w * h * density)
        for (var i = 0; i < count; i++) {
            ctx.globalAlpha = Math.random() * intensity
            var x = Math.random() * w
            var y = Math.random() * h
            ctx.fillRect(x, y, 1, 1)
        }
    }

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
}
