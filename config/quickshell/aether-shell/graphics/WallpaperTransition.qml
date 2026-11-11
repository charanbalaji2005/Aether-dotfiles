import QtQuick
import "../theme"

// Blends two wallpaper images with one of the transition shader's modes.
//
//   WallpaperTransition { from: oldImage; to: newImage; mode: "circle"; progress: p }
//
// `from`/`to` are Image items (texture providers) owned by the caller,
// which keeps them loaded until progress reaches 1 — the old wallpaper is
// never dropped before the new one has decoded, so there is no black frame.
// The caller checks `shaderActive`; when false it cross-fades the two images
// with opacity itself (the original behaviour).
Item {
    id: root

    property Item from: null
    property Item to: null
    property real progress: 0
    property string mode: "fade"
    property point center: Qt.point(0.5, 0.5)
    property point direction: Qt.point(1, 0)
    property real softness: 0.08

    readonly property var modes: ({ "fade": 0, "wipe": 1, "circle": 2, "dissolve": 3, "blinds": 4, "zoom": 5 })
    readonly property bool shaderActive: ShaderLibrary.usable("transition") && from !== null && to !== null

    Loader {
        anchors.fill: parent
        active: root.shaderActive
        sourceComponent: ShaderEffect {
            readonly property var source: root.from
            readonly property var target: root.to
            readonly property real progress: root.progress
            readonly property real mode: root.modes[root.mode] !== undefined ? root.modes[root.mode] : 0
            readonly property real softness: root.softness
            readonly property vector2d dir: Qt.vector2d(root.direction.x, root.direction.y)
            readonly property vector2d center: Qt.vector2d(root.center.x, root.center.y)
            readonly property vector2d size: Qt.vector2d(width, height)
            fragmentShader: ShaderLibrary.url("transition")
            onStatusChanged: ShaderLibrary.reportStatus("transition", status, log)
        }
    }
}
