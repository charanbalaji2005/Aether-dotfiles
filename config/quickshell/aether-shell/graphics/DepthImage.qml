import QtQuick
import "../theme"

// A wallpaper with real depth: `source` is the picture, `depthSource` a
// grey-scale depth map of the same framing (white = near). `offset`
// (-1..1, usually an eased pointer position) moves near pixels more than
// far ones.
//
// Without a depth map — or without shaders — it falls back to a "2.5D"
// shift of the whole picture (a single plane), which still gives a sense
// of motion but no relative depth. That difference is stated in the UI.
Item {
    id: root

    property url source
    property url depthSource
    property point offset: Qt.point(0, 0)
    property real strength: 0.025      // fraction of the image size
    property real focalDepth: 0.35   // depth that stays still (not "focus": Item.focus is FINAL)
    property int sourceWidth: 1920
    property int sourceHeight: 1080
    // Shared decode: an Image elsewhere with the same URL and size reuses
    // this pixmap instead of decoding the file again.
    property bool cache: true
    readonly property real zoom: 1 + strength * 2.2
    readonly property bool hasDepth: depthSource.toString().length > 0 && depth.status === Image.Ready
    readonly property bool trueDepth: hasDepth && ShaderLibrary.usable("parallax")
    readonly property bool ready: picture.status === Image.Ready

    Image {
        id: picture
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: root.cache
        sourceSize.width: root.sourceWidth
        sourceSize.height: root.sourceHeight
        visible: !root.trueDepth
        // 2.5D fallback: the whole plane shifts and is zoomed to hide edges.
        scale: root.zoom
        transform: Translate {
            x: -root.offset.x * root.strength * root.width * 0.5
            y: -root.offset.y * root.strength * root.height * 0.5
        }
    }

    Image {
        id: depth
        visible: false
        source: root.depthSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        width: root.width
        height: root.height
        sourceSize.width: Math.min(root.sourceWidth, 1280)   // depth needs far less resolution
        sourceSize.height: Math.min(root.sourceHeight, 720)
    }

    Loader {
        anchors.fill: parent
        active: root.trueDepth
        sourceComponent: ShaderEffect {
            readonly property var source: picture
            readonly property var depthMap: depth
            readonly property vector2d offset: Qt.vector2d(root.offset.x, root.offset.y)
            readonly property real strength: root.strength
            readonly property real focalDepth: root.focalDepth
            readonly property real zoom: root.zoom
            fragmentShader: ShaderLibrary.url("parallax")
            onStatusChanged: ShaderLibrary.reportStatus("parallax", status, log)
        }
    }
}
