import QtQuick
import "../theme"

// AetherOS's original icon kit, drawn with Canvas so the shell has zero
// icon-font/SVG dependencies. Repaints only when name/colour/size/level
// change — never per frame.
//
// Status icons (pixel-tuned, any aspect ratio):
//   workspace-dot, volume-high, volume-low, volume-mute, wifi (uses `level`
//   0-3), wifi-off, ethernet, battery, battery-charging (use batteryLevel)
// Glyphs (24-unit stroke grid, scaled to fit, square):
//   cpu memory gpu disk thermometer gauge activity mic mic-off bell
//   bell-off bluetooth moon sun contrast bolt leaf display search star
//   star-filled power lock logout clock grid sliders gear image music play
//   pause next prev arrow-up arrow-down chevron-left chevron-right
//   chevron-down check close plus refresh trash globe
Item {
    id: root

    property string name: ""
    property color color: Colors.textPrimary
    property real strokeWidth: 1.6
    property real batteryLevel: 1.0
    property int level: 3

    implicitWidth: 16
    implicitHeight: 16

    onNameChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
    onBatteryLevelChanged: canvas.requestPaint()
    onLevelChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        renderStrategy: Canvas.Cooperative

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
            if (w <= 0 || h <= 0) return;

            switch (root.name) {
            case "workspace-dot":
                ctx.beginPath();
                ctx.arc(w / 2, h / 2, Math.min(w, h) * 0.22, 0, Math.PI * 2);
                ctx.fill();
                return;
            case "volume-high": _drawSpeaker(ctx, w, h, true, false); return;
            case "volume-low": _drawSpeaker(ctx, w, h, false, false); return;
            case "volume-mute": _drawSpeaker(ctx, w, h, false, true); return;
            case "wifi": _drawWifi(ctx, w, h, Math.max(0, Math.min(3, root.level))); return;
            case "wifi-off": _drawWifi(ctx, w, h, 0); return;
            case "ethernet": _drawEthernet(ctx, w, h); return;
            case "battery": _drawBattery(ctx, w, h, false); return;
            case "battery-charging": _drawBattery(ctx, w, h, true); return;
            }

            // Glyphs: map a 24x24 design grid onto the item, centred.
            const s = Math.min(w, h) / 24;
            ctx.save();
            ctx.translate((w - 24 * s) / 2, (h - 24 * s) / 2);
            ctx.scale(s, s);
            ctx.lineWidth = Math.max(1.5, root.strokeWidth / s * 1.15);
            _glyph(ctx, root.name);
            ctx.restore();
        }

        // ── 24-grid glyphs ─────────────────────────────────────────────
        function _line(ctx, x1, y1, x2, y2) { ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke(); }
        function _circle(ctx, x, y, r, fill) { ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); fill ? ctx.fill() : ctx.stroke(); }
        function _rrect(ctx, x, y, w, h, r) {
            ctx.beginPath();
            ctx.moveTo(x + r, y);
            ctx.lineTo(x + w - r, y); ctx.arcTo(x + w, y, x + w, y + r, r);
            ctx.lineTo(x + w, y + h - r); ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
            ctx.lineTo(x + r, y + h); ctx.arcTo(x, y + h, x, y + h - r, r);
            ctx.lineTo(x, y + r); ctx.arcTo(x, y, x + r, y, r);
            ctx.closePath();
        }
        function _poly(ctx, pts, close, fill) {
            ctx.beginPath();
            ctx.moveTo(pts[0], pts[1]);
            for (let i = 2; i < pts.length; i += 2) ctx.lineTo(pts[i], pts[i + 1]);
            if (close) ctx.closePath();
            fill ? ctx.fill() : ctx.stroke();
        }
        function _star(ctx, fill) {
            const pts = [];
            for (let i = 0; i < 10; i++) {
                const r = i % 2 === 0 ? 9.5 : 4.2;
                const a = -Math.PI / 2 + i * Math.PI / 5;
                pts.push(12 + r * Math.cos(a), 12.8 + r * Math.sin(a));
            }
            _poly(ctx, pts, true, fill);
        }

        function _glyph(ctx, n) {
            switch (n) {
            case "cpu":
                _rrect(ctx, 6, 6, 12, 12, 2); ctx.stroke();
                _rrect(ctx, 9.5, 9.5, 5, 5, 1); ctx.stroke();
                [9, 12, 15].forEach(function(p) {
                    _line(ctx, p, 2.5, p, 6); _line(ctx, p, 18, p, 21.5);
                    _line(ctx, 2.5, p, 6, p); _line(ctx, 18, p, 21.5, p);
                });
                break;
            case "memory":
                _rrect(ctx, 2.5, 7, 19, 9, 1.5); ctx.stroke();
                [6.5, 10.5, 14.5].forEach(function(x) { _rrect(ctx, x, 9.5, 3, 4, 0.5); ctx.stroke(); });
                [5, 9, 13, 17].forEach(function(x) { _line(ctx, x, 16, x, 19); });
                break;
            case "gpu":
                _rrect(ctx, 2.5, 6, 19, 11, 2); ctx.stroke();
                _circle(ctx, 9, 11.5, 3, false);
                _line(ctx, 15, 9.5, 18.5, 9.5); _line(ctx, 15, 13.5, 18.5, 13.5);
                _line(ctx, 5, 17, 5, 20); _line(ctx, 9, 17, 9, 20);
                break;
            case "disk":
                _rrect(ctx, 3, 5, 18, 14, 2.5); ctx.stroke();
                _line(ctx, 3, 13, 21, 13);
                _circle(ctx, 17, 16, 0.9, true);
                break;
            case "thermometer":
                ctx.beginPath(); ctx.moveTo(10, 14.5); ctx.lineTo(10, 5); ctx.arc(12, 5, 2, Math.PI, 0); ctx.lineTo(14, 14.5); ctx.stroke();
                ctx.beginPath(); ctx.arc(12, 17.5, 3.6, -Math.PI * 0.32, Math.PI * 1.32); ctx.stroke();
                _circle(ctx, 12, 17.5, 1.6, true);
                _line(ctx, 12, 16, 12, 9);
                break;
            case "gauge":
                ctx.beginPath(); ctx.arc(12, 14, 9, Math.PI * 0.9, Math.PI * 2.1); ctx.stroke();
                _line(ctx, 12, 14, 16.5, 8.5);
                _circle(ctx, 12, 14, 1.4, true);
                break;
            case "activity":
                _poly(ctx, [2.5, 12, 7, 12, 10, 4, 14, 20, 17, 12, 21.5, 12], false, false);
                break;
            case "mic":
            case "mic-off":
                _rrect(ctx, 9, 3, 6, 11, 3); ctx.stroke();
                ctx.beginPath(); ctx.arc(12, 11, 6.5, 0, Math.PI); ctx.stroke();
                _line(ctx, 12, 17.5, 12, 21); _line(ctx, 8.5, 21, 15.5, 21);
                if (n === "mic-off") _line(ctx, 3.5, 3.5, 20.5, 20.5);
                break;
            case "bell":
            case "bell-off":
                ctx.beginPath(); ctx.moveTo(5, 17); ctx.lineTo(6.5, 15); ctx.lineTo(6.5, 10.5);
                ctx.arc(12, 10.5, 5.5, Math.PI, 0); ctx.lineTo(17.5, 15); ctx.lineTo(19, 17); ctx.closePath(); ctx.stroke();
                ctx.beginPath(); ctx.arc(12, 19, 2, 0, Math.PI); ctx.stroke();
                if (n === "bell-off") _line(ctx, 3.5, 3.5, 20.5, 20.5);
                break;
            case "bluetooth":
                _poly(ctx, [7, 7.5, 17, 16.5, 12, 21, 12, 3, 17, 7.5, 7, 16.5], false, false);
                break;
            case "moon":
                ctx.beginPath(); ctx.arc(12, 12, 8.5, Math.PI * 0.25, Math.PI * 1.75);
                ctx.arc(16.5, 8.5, 6.4, Math.PI * 1.36, Math.PI * 0.64, true); ctx.stroke();
                break;
            case "sun":
                _circle(ctx, 12, 12, 4, false);
                for (let i = 0; i < 8; i++) {
                    const a = i * Math.PI / 4;
                    _line(ctx, 12 + 7 * Math.cos(a), 12 + 7 * Math.sin(a), 12 + 9.5 * Math.cos(a), 12 + 9.5 * Math.sin(a));
                }
                break;
            case "contrast":
                _circle(ctx, 12, 12, 8.5, false);
                ctx.beginPath(); ctx.arc(12, 12, 8.5, -Math.PI / 2, Math.PI / 2); ctx.closePath(); ctx.fill();
                break;
            case "bolt":
                _poly(ctx, [13.5, 2.5, 5, 13.5, 11.5, 13.5, 10.5, 21.5, 19, 10.5, 12.5, 10.5], true, false);
                break;
            case "leaf":
                ctx.beginPath(); ctx.moveTo(5, 19); ctx.bezierCurveTo(4, 9, 10, 4, 20, 4); ctx.bezierCurveTo(20, 14, 15, 20, 5, 19); ctx.stroke();
                _line(ctx, 5, 19, 14, 10);
                break;
            case "display":
                _rrect(ctx, 2.5, 4, 19, 12.5, 2); ctx.stroke();
                _line(ctx, 12, 16.5, 12, 20); _line(ctx, 8, 20.5, 16, 20.5);
                break;
            case "search":
                _circle(ctx, 10.5, 10.5, 6.5, false);
                _line(ctx, 15.5, 15.5, 20.5, 20.5);
                break;
            case "star": _star(ctx, false); break;
            case "star-filled": _star(ctx, true); break;
            case "power":
                ctx.beginPath(); ctx.arc(12, 13, 8, -Math.PI * 0.3, Math.PI * 1.3); ctx.stroke();
                _line(ctx, 12, 3, 12, 12);
                break;
            case "lock":
                _rrect(ctx, 5, 10.5, 14, 10, 2); ctx.stroke();
                ctx.beginPath(); ctx.moveTo(8, 10.5); ctx.lineTo(8, 7.5); ctx.arc(12, 7.5, 4, Math.PI, 0); ctx.lineTo(16, 10.5); ctx.stroke();
                break;
            case "clipboard":
                _rrect(ctx, 5.5, 5, 13, 16, 2); ctx.stroke();
                _rrect(ctx, 9, 3, 6, 4, 1.2); ctx.stroke();
                _line(ctx, 9, 12, 15, 12); _line(ctx, 9, 16, 13, 16);
                break;
            case "camera":
                _rrect(ctx, 3, 7, 13, 10, 2); ctx.stroke();
                _poly(ctx, [16, 10.5, 21, 7.5, 21, 16.5, 16, 13.5], true, false);
                break;
            case "keyboard":
                _rrect(ctx, 2.5, 6, 19, 12, 2); ctx.stroke();
                for (let kx = 6; kx <= 18; kx += 4) { _line(ctx, kx, 10, kx + 0.01, 10); }
                _line(ctx, 8, 14.5, 16, 14.5);
                break;
            case "mouse":
                _rrect(ctx, 7, 3.5, 10, 17, 5); ctx.stroke();
                _line(ctx, 12, 7, 12, 10);
                break;
            case "sparkle":
                _poly(ctx, [12, 3, 13.8, 10.2, 21, 12, 13.8, 13.8, 12, 21, 10.2, 13.8, 3, 12, 10.2, 10.2], true, false);
                _line(ctx, 19, 3.5, 19, 6.5); _line(ctx, 17.5, 5, 20.5, 5);
                break;
            case "widgets":
                _rrect(ctx, 3.5, 3.5, 7.5, 7.5, 1.6); ctx.stroke();
                _rrect(ctx, 13, 3.5, 7.5, 7.5, 1.6); ctx.stroke();
                _rrect(ctx, 3.5, 13, 7.5, 7.5, 1.6); ctx.stroke();
                _circle(ctx, 16.75, 16.75, 3.75, false);
                break;
            case "shield":
                _poly(ctx, [12, 3, 19.5, 6, 19, 12.5, 12, 21, 5, 12.5, 4.5, 6], true, false);
                _poly(ctx, [9, 12, 11.2, 14.2, 15.5, 9.8], false, false);
                break;
            case "archive":
                _rrect(ctx, 3.5, 4, 17, 5, 1.2); ctx.stroke();
                _poly(ctx, [5, 9, 5, 20, 19, 20, 19, 9], false, false);
                _line(ctx, 10, 13, 14, 13);
                break;
            case "code":
                _poly(ctx, [8.5, 7, 3.5, 12, 8.5, 17], false, false);
                _poly(ctx, [15.5, 7, 20.5, 12, 15.5, 17], false, false);
                _line(ctx, 13.5, 5, 10.5, 19);
                break;
            case "logout":
                _poly(ctx, [10, 4, 5, 4, 5, 20, 10, 20], false, false);
                _line(ctx, 10, 12, 20, 12);
                _poly(ctx, [16, 8, 20, 12, 16, 16], false, false);
                break;
            case "clock":
                _circle(ctx, 12, 12, 8.5, false);
                _poly(ctx, [12, 7, 12, 12, 15.5, 14], false, false);
                break;
            case "grid":
                [[4, 4], [13.5, 4], [4, 13.5], [13.5, 13.5]].forEach(function(p) { _rrect(ctx, p[0], p[1], 6.5, 6.5, 1.8); ctx.stroke(); });
                break;
            case "sliders":
                _line(ctx, 4, 7, 20, 7); _line(ctx, 4, 17, 20, 17);
                _circle(ctx, 9, 7, 2.4, true); _circle(ctx, 15, 17, 2.4, true);
                break;
            case "gear":
                _circle(ctx, 12, 12, 3, false);
                for (let i = 0; i < 8; i++) {
                    const a = i * Math.PI / 4;
                    _line(ctx, 12 + 6 * Math.cos(a), 12 + 6 * Math.sin(a), 12 + 9 * Math.cos(a), 12 + 9 * Math.sin(a));
                }
                _circle(ctx, 12, 12, 6.2, false);
                break;
            case "image":
                _rrect(ctx, 3, 4, 18, 16, 2.5); ctx.stroke();
                _circle(ctx, 8.5, 9.5, 1.8, false);
                _poly(ctx, [3.5, 18, 10, 12, 14, 15.5, 16.5, 13, 20.5, 17], false, false);
                break;
            case "music":
                _poly(ctx, [9, 17.5, 9, 5, 19, 3, 19, 15.5], false, false);
                _circle(ctx, 6.5, 17.5, 2.5, false); _circle(ctx, 16.5, 15.5, 2.5, false);
                break;
            case "play": _poly(ctx, [7, 4.5, 19, 12, 7, 19.5], true, true); break;
            case "pause":
                _rrect(ctx, 6, 5, 4, 14, 1); ctx.fill();
                _rrect(ctx, 14, 5, 4, 14, 1); ctx.fill();
                break;
            case "next": _poly(ctx, [5, 5, 15, 12, 5, 19], true, true); _line(ctx, 18.5, 5, 18.5, 19); break;
            case "prev": _poly(ctx, [19, 5, 9, 12, 19, 19], true, true); _line(ctx, 5.5, 5, 5.5, 19); break;
            case "arrow-up": _line(ctx, 12, 20, 12, 4); _poly(ctx, [6, 10, 12, 4, 18, 10], false, false); break;
            case "arrow-down": _line(ctx, 12, 4, 12, 20); _poly(ctx, [6, 14, 12, 20, 18, 14], false, false); break;
            case "chevron-left": _poly(ctx, [15, 5, 8, 12, 15, 19], false, false); break;
            case "chevron-right": _poly(ctx, [9, 5, 16, 12, 9, 19], false, false); break;
            case "chevron-down": _poly(ctx, [5, 9, 12, 16, 19, 9], false, false); break;
            case "check": _poly(ctx, [4.5, 12.5, 9.5, 17.5, 19.5, 6.5], false, false); break;
            case "close": _line(ctx, 6, 6, 18, 18); _line(ctx, 18, 6, 6, 18); break;
            case "plus": _line(ctx, 12, 5, 12, 19); _line(ctx, 5, 12, 19, 12); break;
            case "refresh":
                ctx.beginPath(); ctx.arc(12, 12, 8, -Math.PI * 0.15, Math.PI * 1.55); ctx.stroke();
                _poly(ctx, [19.5, 4, 19.8, 9.2, 14.8, 8.6], false, false);
                break;
            case "trash":
                _line(ctx, 4, 6.5, 20, 6.5);
                _poly(ctx, [9, 6.5, 9.5, 3.5, 14.5, 3.5, 15, 6.5], false, false);
                _poly(ctx, [6, 6.5, 7, 20.5, 17, 20.5, 18, 6.5], false, false);
                break;
            case "globe":
                _circle(ctx, 12, 12, 9, false);
                ctx.beginPath(); ctx.ellipse(8, 3, 8, 18); ctx.stroke();
                _line(ctx, 3, 12, 21, 12);
                break;
            default:
                _circle(ctx, 12, 12, 7, false);
            }
        }

        // ── Pixel-tuned status icons (unchanged from the original kit) ──
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
