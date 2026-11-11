import QtQuick
import QtQuick.Shapes
import "../theme"
import "../animation"

// AetherOS battery glyph families (Settings → Battery). All are drawn from
// primitives (no image assets), recolour with the theme, and animate only
// while charging (a slow sweep) — and not at all under reduced motion.
//
//   classic    rounded body + nub, fill level
//   outline    thin body, inset fill, no colour block
//   filled     solid body; level shown by a darker empty part
//   segmented  five cells
//   circular   ring gauge
//   percent    the number only
//   compact    narrow vertical pill
//   bar        thin horizontal level bar
//
// `level` 0-1, `charging`, `state` "normal"|"low"|"critical"|"charging"|"full".
Item {
    id: root

    property string style: "classic"
    property real level: 1.0
    property bool charging: false
    property bool saver: false
    property string state: "normal"
    property color colorNormal: Colors.textPrimary
    property color colorLow: Colors.warning
    property color colorCritical: Colors.danger
    property color colorCharging: Colors.success
    property bool showPercent: false

    readonly property color tone: charging || state === "full" ? colorCharging
        : state === "critical" ? colorCritical
        : state === "low" ? colorLow
        : colorNormal
    readonly property real lvl: Math.max(0, Math.min(1, level))

    implicitWidth: style === "circular" ? 18 : style === "compact" ? 10 : style === "percent" ? pct.implicitWidth : style === "bar" ? 26 : 24
    implicitHeight: style === "circular" ? 18 : style === "compact" ? 18 : 12

    SpringValue { id: shown; preset: "smooth"; target: root.lvl }
    Component.onCompleted: shown.snap(root.lvl)

    // Charging sweep, 0-1, only while charging and visible.
    property real sweep: 0
    NumberAnimation on sweep {
        from: 0; to: 1; duration: 1800; loops: Animation.Infinite
        running: root.charging && root.visible && Motion.animate
    }

    // ── classic / outline / filled ────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: root.style === "classic" || root.style === "outline" || root.style === "filled"
        Rectangle {
            id: body
            x: 0; y: 0
            width: parent.width - 3
            height: parent.height
            radius: 3
            color: root.style === "filled" ? Colors.withAlpha(root.tone, 0.28) : "transparent"
            border.width: root.style === "outline" ? 1 : 1.4
            border.color: Colors.withAlpha(root.tone, root.style === "filled" ? 0 : 0.85)
            Rectangle {
                x: root.style === "filled" ? 0 : 2
                y: root.style === "filled" ? 0 : 2
                height: parent.height - (root.style === "filled" ? 0 : 4)
                width: Math.max(0, (parent.width - (root.style === "filled" ? 0 : 4)) * shown.value)
                radius: root.style === "filled" ? 3 : 1.5
                color: root.style === "outline" ? Colors.withAlpha(root.tone, 0.65) : root.tone
                clip: true
                Rectangle {
                    visible: root.charging && Motion.animate
                    width: parent.width * 0.4; height: parent.height
                    x: -width + (parent.width + width) * root.sweep
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.55) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
            }
        }
        Rectangle {
            x: body.width + 0.5; width: 2; height: parent.height * 0.42
            anchors.verticalCenter: parent.verticalCenter
            radius: 1
            color: Colors.withAlpha(root.tone, 0.85)
        }
        // Charging bolt / saver leaf overlay.
        AetherIcon {
            visible: root.charging || root.saver
            anchors.centerIn: body
            width: body.height; height: body.height
            name: root.charging ? "bolt" : "leaf"
            color: root.style === "filled" ? Colors.bg0 : Colors.textPrimary
            strokeWidth: 1.4
        }
    }

    // ── segmented ─────────────────────────────────────────────────────
    Row {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.style === "segmented"
        spacing: 1.5
        Repeater {
            model: 5
            delegate: Rectangle {
                required property int index
                width: (root.width - 6) / 5; height: root.height
                radius: 1.5
                readonly property bool lit: shown.value > index / 5 + 0.02
                color: lit ? root.tone : Colors.withAlpha(root.tone, 0.18)
                opacity: root.charging && Math.floor(root.sweep * 5) === index ? 0.55 : 1
            }
        }
    }

    // ── circular ──────────────────────────────────────────────────────
    Shape {
        anchors.fill: parent
        visible: root.style === "circular"
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Colors.withAlpha(root.tone, 0.2); strokeWidth: 2.4; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.width / 2 - 1.5; radiusY: radiusX; startAngle: -90; sweepAngle: 360 }
        }
        ShapePath {
            strokeColor: root.tone; strokeWidth: 2.4; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.width / 2 - 1.5; radiusY: radiusX; startAngle: -90 + (root.charging ? 360 * root.sweep : 0); sweepAngle: 360 * shown.value }
        }
    }

    // ── compact (vertical) ───────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: root.style === "compact"
        radius: width / 2
        color: "transparent"
        border.width: 1.2
        border.color: Colors.withAlpha(root.tone, 0.85)
        Rectangle {
            anchors.bottom: parent.bottom; anchors.bottomMargin: 2
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 4
            height: Math.max(width, (parent.height - 4) * shown.value)
            radius: width / 2
            color: root.tone
        }
    }

    // ── bar ──────────────────────────────────────────────────────────
    Rectangle {
        visible: root.style === "bar"
        anchors.verticalCenter: parent.verticalCenter
        width: root.width; height: 4; radius: 2
        color: Colors.withAlpha(root.tone, 0.2)
        Rectangle { width: parent.width * shown.value; height: parent.height; radius: 2; color: root.tone }
    }

    // ── percent ──────────────────────────────────────────────────────
    Text {
        id: pct
        visible: root.style === "percent"
        anchors.verticalCenter: parent.verticalCenter
        text: (root.charging ? "⚡" : "") + Math.round(root.lvl * 100) + "%"
        color: root.tone
        font.family: Typography.family
        font.pixelSize: Typography.sizeSm
        font.weight: Typography.weightSemibold
        font.features: { "tnum": 1 }
    }
}
