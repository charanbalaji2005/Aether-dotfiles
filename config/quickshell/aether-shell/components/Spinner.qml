import QtQuick
import "../theme"

// Loading indicator. The rotation only runs while the spinner is visible,
// so a hidden spinner costs nothing. Under reduced motion it shows a static
// partial ring instead of spinning.
Item {
    id: root

    property color color: Colors.accent
    property real thickness: 2

    implicitWidth: 18
    implicitHeight: 18

    Canvas {
        id: ring
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = root.color;
            ctx.lineWidth = root.thickness;
            ctx.lineCap = "round";
            const r = Math.min(width, height) / 2 - root.thickness;
            ctx.beginPath();
            ctx.arc(width / 2, height / 2, r, 0, Math.PI * 1.4);
            ctx.stroke();
        }
        RotationAnimator on rotation {
            from: 0
            to: 360
            duration: 900
            loops: Animation.Infinite
            running: root.visible && !Motion.reducedMotion
        }
    }

    onColorChanged: ring.requestPaint()
}
