import QtQuick
import "../theme"

// Filled line graph for a short history of 0-1 values (oldest first).
// Repaints only when `values` changes (once per telemetry sample) and only
// while visible — there is no animation loop.
Item {
    id: root

    property var values: []
    property color lineColor: Colors.accent
    property real fillOpacity: 0.22
    property real maxValue: 1.0
    property bool showGrid: true

    implicitHeight: 48

    onValuesChanged: if (visible) canvas.requestPaint()
    onLineColorChanged: canvas.requestPaint()
    onVisibleChanged: if (visible) canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const w = width, h = height;
            const vals = root.values || [];
            if (w <= 0 || h <= 0) return;

            if (root.showGrid) {
                ctx.strokeStyle = Colors.withAlpha(Colors.textMuted, 0.15);
                ctx.lineWidth = 1;
                for (let i = 1; i < 4; i++) {
                    const gy = Math.round(h * i / 4) + 0.5;
                    ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke();
                }
            }
            if (vals.length < 2) return;

            const maxV = root.maxValue > 0 ? root.maxValue : 1;
            const step = w / (vals.length - 1);
            function yAt(v) {
                const n = Math.max(0, Math.min(1, (v === null || v === undefined ? 0 : v) / maxV));
                return h - 1 - n * (h - 3);
            }

            ctx.beginPath();
            ctx.moveTo(0, yAt(vals[0]));
            for (let i = 1; i < vals.length; i++) ctx.lineTo(i * step, yAt(vals[i]));
            ctx.lineTo(w, h);
            ctx.lineTo(0, h);
            ctx.closePath();
            const grad = ctx.createLinearGradient(0, 0, 0, h);
            grad.addColorStop(0, Colors.withAlpha(root.lineColor, root.fillOpacity));
            grad.addColorStop(1, Colors.withAlpha(root.lineColor, 0));
            ctx.fillStyle = grad;
            ctx.fill();

            ctx.beginPath();
            ctx.moveTo(0, yAt(vals[0]));
            for (let j = 1; j < vals.length; j++) ctx.lineTo(j * step, yAt(vals[j]));
            ctx.strokeStyle = root.lineColor;
            ctx.lineWidth = 1.6;
            ctx.lineJoin = "round";
            ctx.stroke();
        }
    }
}
