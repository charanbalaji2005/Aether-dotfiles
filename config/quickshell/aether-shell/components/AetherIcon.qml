import QtQuick
import "../theme"

// A small original icon kit drawn directly with Canvas rather than an
// external icon font or SVG set, so Phase 1 has zero asset dependencies.
// Supported names: workspace-dot, volume-high, volume-low, volume-mute,
// wifi, wifi-off, ethernet, battery, battery-charging.
Item {
    id: root

    property string name: ""
    property color color: Colors.textPrimary
    property real strokeWidth: 1.6
    property real batteryLevel: 1.0

    implicitWidth: 16
    implicitHeight: 16

    onNameChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
    onBatteryLevelChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = root.color;
            ctx.fillStyle = root.color;
            ctx.lineWidth = root.strokeWidth;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";

            const w = width;
            const h = height;

            switch (root.name) {
            case "workspace-dot":
                ctx.beginPath();
                ctx.arc(w / 2, h / 2, Math.min(w, h) * 0.22, 0, Math.PI * 2);
                ctx.fill();
                break;
            case "volume-high":
                _drawSpeaker(ctx, w, h, true, false);
                break;
            case "volume-low":
                _drawSpeaker(ctx, w, h, false, false);
                break;
            case "volume-mute":
                _drawSpeaker(ctx, w, h, false, true);
                break;
            case "wifi":
                _drawWifi(ctx, w, h, 3);
                break;
            case "wifi-off":
                _drawWifi(ctx, w, h, 0);
                break;
            case "ethernet":
                _drawEthernet(ctx, w, h);
                break;
            case "battery":
                _drawBattery(ctx, w, h, false);
                break;
            case "battery-charging":
                _drawBattery(ctx, w, h, true);
                break;
            default:
                ctx.beginPath();
                ctx.arc(w / 2, h / 2, Math.min(w, h) * 0.3, 0, Math.PI * 2);
                ctx.stroke();
            }
        }

        function _drawSpeaker(ctx, w, h, loud, muted) {
            const bodyW = w * 0.34;
            const bodyH = h * 0.4;
            const x = w * 0.14;
            const y = (h - bodyH) / 2;

            ctx.beginPath();
            ctx.moveTo(x, y + bodyH * 0.25);
            ctx.lineTo(x + bodyW * 0.5, y + bodyH * 0.25);
            ctx.lineTo(x + bodyW, y);
            ctx.lineTo(x + bodyW, y + bodyH);
            ctx.lineTo(x + bodyW * 0.5, y + bodyH * 0.75);
            ctx.lineTo(x, y + bodyH * 0.75);
            ctx.closePath();
            ctx.fill();

            if (muted) {
                ctx.beginPath();
                ctx.moveTo(x + bodyW * 1.2, h * 0.3);
                ctx.lineTo(w * 0.9, h * 0.7);
                ctx.moveTo(w * 0.9, h * 0.3);
                ctx.lineTo(x + bodyW * 1.2, h * 0.7);
                ctx.stroke();
            } else {
                ctx.beginPath();
                ctx.arc(x + bodyW * 0.9, h / 2, w * 0.16, -Math.PI * 0.32, Math.PI * 0.32);
                ctx.stroke();
                if (loud) {
                    ctx.beginPath();
                    ctx.arc(x + bodyW * 0.9, h / 2, w * 0.3, -Math.PI * 0.3, Math.PI * 0.3);
                    ctx.stroke();
                }
            }
        }

        function _drawWifi(ctx, w, h, bars) {
            const cx = w / 2;
            const baseY = h * 0.82;
            for (let i = 0; i < 3; i++) {
                const radius = (i + 1) * (w * 0.24);
                const active = i < bars;
                ctx.globalAlpha = active ? 1.0 : 0.28;
                ctx.beginPath();
                ctx.arc(cx, baseY, radius, Math.PI * 1.22, Math.PI * 1.78);
                ctx.stroke();
            }
            ctx.globalAlpha = 1.0;
            ctx.beginPath();
            ctx.arc(cx, baseY, w * 0.06, 0, Math.PI * 2);
            ctx.fill();
        }

        function _drawEthernet(ctx, w, h) {
            ctx.beginPath();
            ctx.moveTo(w * 0.5, h * 0.15);
            ctx.lineTo(w * 0.5, h * 0.5);
            ctx.moveTo(w * 0.25, h * 0.5);
            ctx.lineTo(w * 0.75, h * 0.5);
            ctx.moveTo(w * 0.25, h * 0.5);
            ctx.lineTo(w * 0.25, h * 0.68);
            ctx.moveTo(w * 0.75, h * 0.5);
            ctx.lineTo(w * 0.75, h * 0.68);
            ctx.stroke();

            [0.25, 0.75].forEach(function(fx) {
                ctx.beginPath();
                ctx.rect(w * fx - w * 0.08, h * 0.68, w * 0.16, h * 0.2);
                ctx.stroke();
            });
        }

        function _drawBattery(ctx, w, h, charging) {
            const bodyW = w * 0.76;
            const bodyH = h * 0.6;
            const x = w * 0.04;
            const y = (h - bodyH) / 2;
            const capW = w * 0.06;

            ctx.beginPath();
            ctx.rect(x, y, bodyW, bodyH);
            ctx.stroke();
            ctx.fillRect(x + bodyW, y + bodyH * 0.25, capW, bodyH * 0.5);

            const ratio = Math.max(0, Math.min(1, root.batteryLevel));
            const inset = 2;
            ctx.fillRect(x + inset, y + inset, Math.max(0, (bodyW - inset * 2) * ratio), bodyH - inset * 2);

            if (charging) {
                ctx.beginPath();
                ctx.moveTo(x + bodyW * 0.55, y);
                ctx.lineTo(x + bodyW * 0.3, y + bodyH * 0.55);
                ctx.lineTo(x + bodyW * 0.5, y + bodyH * 0.55);
                ctx.lineTo(x + bodyW * 0.4, y + bodyH);
                ctx.lineTo(x + bodyW * 0.75, y + bodyH * 0.4);
                ctx.lineTo(x + bodyW * 0.5, y + bodyH * 0.4);
                ctx.closePath();
                ctx.fill();
            }
        }
    }
}
