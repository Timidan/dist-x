import QtQuick

Canvas {
    id: root
    property var theme
    property var points: []     // array of numbers
    property color stroke: theme ? theme.accent : "#1E40AF"
    property real strokeWidth: 1.5

    height: 50

    onPointsChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onStrokeChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        if (!points || points.length < 2) return

        var w = width, h = height
        var min = Math.min.apply(null, points)
        var max = Math.max.apply(null, points)
        var range = (max - min) || 1
        var stepX = w / (points.length - 1)

        ctx.lineWidth = strokeWidth
        ctx.strokeStyle = stroke
        ctx.beginPath()
        for (var i = 0; i < points.length; i++) {
            var x = i * stepX
            var y = h - ((points[i] - min) / range) * (h - 4) - 2
            if (i === 0) ctx.moveTo(x, y)
            else ctx.lineTo(x, y)
        }
        ctx.stroke()
    }
}
