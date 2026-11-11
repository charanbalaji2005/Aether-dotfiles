import QtQuick
import "../theme"
import "../animation"

// The frost layer of a glass surface (grain, pointer-following specular,
// lit rim). Place it over a surface's tint, same size; it never
// intercepts input.
//
// Costs: one ShaderEffect, static unless the pointer moves over it (then
// the light eases towards the pointer with a spring and stops when it
// arrives). Absent entirely in the eco tier, with shaders disabled, or if
// the shader failed to load — the surface underneath already looks right
// without it.
Loader {
    id: root

    property real radius: Metrics.radiusMd
    property real frost: Materials.frost
    property real specular: Materials.specular
    property real rim: Colors.dark ? 0.5 : 0.8
    // Set by the owner from a HoverHandler (0-1 coordinates) and hovered flag.
    property point pointer: Qt.point(0.5, 0.0)
    property bool pointerInside: false

    active: ShaderLibrary.usable("glass") && !Effects.eco && (frost > 0 || specular > 0)
    asynchronous: false

    sourceComponent: ShaderEffect {
        id: fx
        readonly property vector2d size: Qt.vector2d(width, height)
        readonly property real radius: root.radius
        readonly property real frost: root.frost
        readonly property real specular: Effects.lightFollow ? root.specular : 0
        readonly property vector2d lightPos: Qt.vector2d(lx.value, ly.value)
        readonly property real lightActive: la.value
        readonly property color rimColor: Colors.highlight
        readonly property real rim: root.rim

        fragmentShader: ShaderLibrary.url("glass")
        onStatusChanged: ShaderLibrary.reportStatus("glass", status, log)

        SpringValue { id: lx; target: root.pointer.x; preset: "fluid" }
        SpringValue { id: ly; target: root.pointer.y; preset: "fluid" }
        SpringValue { id: la; target: root.pointerInside && Effects.lightFollow ? 1 : 0; preset: "gentle" }
    }
}
