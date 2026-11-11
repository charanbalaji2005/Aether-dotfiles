import QtQuick
import "../theme"

// Animated ambient gradient (lock screen, idle backdrops). Time only
// advances while `running`, the item is visible and ambient effects are
// allowed; otherwise it renders a still frame. Fallback: a two-stop
// gradient in the same colours.
Item {
    id: root

    property color base: Colors.bg0
    property color colorA: Colors.accent
    property color colorB: Colors.accentAlt
    property color colorC: Colors.info
    property real strength: Colors.dark ? 0.42 : 0.28
    property bool running: true

    readonly property bool _shader: ShaderLibrary.usable("aurora") && !Effects.eco

    Loader {
        anchors.fill: parent
        active: root._shader
        sourceComponent: ShaderEffect {
            property real time: 37   // a pleasant still frame when not running
            readonly property vector2d size: Qt.vector2d(width, height)
            readonly property color base: root.base
            readonly property color colorA: root.colorA
            readonly property color colorB: root.colorB
            readonly property color colorC: root.colorC
            readonly property real strength: root.strength
            fragmentShader: ShaderLibrary.url("aurora")
            onStatusChanged: ShaderLibrary.reportStatus("aurora", status, log)

            NumberAnimation on time {
                from: 37; to: 37 + 3600
                duration: 3600 * 1000
                loops: Animation.Infinite
                running: root.running && root.visible && Effects.ambient && Motion.animate
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: !root._shader
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.mix(root.base, root.colorA, root.strength * 0.5) }
            GradientStop { position: 0.6; color: root.base }
            GradientStop { position: 1.0; color: Colors.mix(root.base, root.colorB, root.strength * 0.35) }
        }
    }
}
