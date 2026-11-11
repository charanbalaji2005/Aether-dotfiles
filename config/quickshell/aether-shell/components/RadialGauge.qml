import QtQuick
import QtQuick.Shapes
import "../theme"
import "../animation"

// Arc gauge for a 0-1 metric (dashboard CPU/GPU/RAM, temperatures).
// The arc follows the value on a spring, so a 2 s telemetry tick becomes a
// smooth sweep; the colour moves through accent → warning → danger.
// Unavailable metrics show an empty track and a dash, never a fake zero.
Item {
    id: root

    property real value: 0             // 0-1
    property bool available: true
    property string label: ""
    property string valueText: available ? Math.round(value * 100) + "%" : "—"
    property string detail: ""
    property real thickness: 7
    property real sweep: 270           // degrees of the full track
    property color color: Colors.load(value)

    implicitWidth: 112
    implicitHeight: 112

    SpringValue { id: v; preset: "smooth"; target: root.available ? Math.max(0, Math.min(1, root.value)) : 0 }

    readonly property real r: Math.min(width, height) / 2 - thickness / 2 - 1
    readonly property real startAngle: 90 + (360 - sweep) / 2

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Colors.withAlpha(Colors.textMuted, 0.18)
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.r; radiusY: root.r; startAngle: root.startAngle; sweepAngle: root.sweep }
        }
        ShapePath {
            // A zero-length round-capped arc would still draw a dot.
            strokeColor: v.value > 0.003 ? root.color : "transparent"
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.r; radiusY: root.r; startAngle: root.startAngle; sweepAngle: Math.max(0.01, root.sweep * v.value) }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 0
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.valueText
            color: Colors.textPrimary
            font.family: Typography.familyDisplay
            font.pixelSize: Math.round(root.height * 0.2)
            font.weight: Typography.weightSemibold
            font.features: { "tnum": 1 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Colors.textMuted
            font.family: Typography.family
            font.pixelSize: Typography.sizeXs
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.8
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.detail.length > 0
            text: root.detail
            color: Colors.textSecondary
            font.family: Typography.family
            font.pixelSize: Typography.sizeXs
        }
    }
}
