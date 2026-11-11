import QtQuick
import "../theme"

// Neon edge illumination for a rounded rectangle. Anchor it to the surface
// it decorates (`anchors.fill: card`); it extends `spread` px outside.
//
//   GlowEdge { anchors.fill: card; radius: card.radius; active: panel.open }
//
// While `active`, a highlight travels around the edge (one lap per
// `period` ms); otherwise it holds still. The animation stops whenever the
// edge is invisible, glow is off, or motion is reduced. Fallback (eco /
// no shaders): a plain 1 px accent border.
Item {
    id: root

    property real radius: Metrics.radiusLg
    property real spread: 14
    property real thickness: 1.4
    property real intensity: 0.85
    property color colorA: Colors.accent
    property color colorB: Colors.accentAlt
    property bool active: true
    property int period: 5200

    readonly property bool _shader: ShaderLibrary.usable("glow") && Effects.glow && !Effects.eco

    Loader {
        x: -root.spread
        y: -root.spread
        width: root.width + root.spread * 2
        height: root.height + root.spread * 2
        active: root._shader && root.visible && root.opacity > 0
        sourceComponent: ShaderEffect {
            id: fx
            readonly property vector2d size: Qt.vector2d(width, height)
            readonly property real radius: root.radius
            readonly property real spread: root.spread
            readonly property real thickness: root.thickness
            property real phase: 0
            readonly property real intensity: root.intensity
            readonly property color colorA: root.colorA
            readonly property color colorB: root.colorB
            fragmentShader: ShaderLibrary.url("glow")
            onStatusChanged: ShaderLibrary.reportStatus("glow", status, log)

            NumberAnimation on phase {
                from: 0; to: 1
                duration: root.period
                loops: Animation.Infinite
                running: root.active && Motion.animate && root.visible
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: !root._shader && Effects.glow
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Colors.withAlpha(root.colorA, 0.55 * root.intensity)
    }
}
