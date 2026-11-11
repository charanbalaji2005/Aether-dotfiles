import QtQuick
import "../theme"
import "../animation"

// The wallpaper renderer: two image layers, transitions and parallax.
// Pure Qt Quick (no Quickshell, no services) so it is runtime-tested by
// tests/shell/runtime/tst_wallpaper_stage.qml; WallpaperBackground feeds it.
//
// Changing `path`:
//   1. the new image decodes into the back layer (asynchronously, at
//      `sourceWidth`×`sourceHeight` — never at a huge source's native size);
//   2. only when it's Ready does the transition start, so the old picture
//      is never replaced by a black frame;
//   3. `transition` plays: fade, zoom, wipe, circle, dissolve, blinds on
//      the transition shader; slide in QML; shader modes fall back to fade
//      when shaders are unavailable; "none" or reduced motion = instant;
//   4. the layers swap and the old image is dropped (all layers share one
//      decode per file through the pixmap cache).
Item {
    id: root

    property string path: ""
    property string transition: "fade"
    property int duration: 900
    property string depthPath: ""            // grey-scale depth map for `path`, or ""
    property bool parallax: false
    property point offset: Qt.point(0, 0)    // -1..1, already eased by the caller
    property real parallaxStrength: 0.35     // 0-1
    property bool playGif: false
    property int sourceWidth: Math.max(1, width)
    property int sourceHeight: Math.max(1, height)

    readonly property bool transitioning: progress < 1
    readonly property string shownPath: front === 0 ? pathA : pathB
    signal transitionStarted(string mode)
    signal transitionFinished()

    property int front: 0
    property string pathA: ""
    property string pathB: ""
    property real progress: 1
    property string mode: "fade"
    readonly property Image frontImage: front === 0 ? imgA : imgB
    readonly property Image backImage: front === 0 ? imgB : imgA
    readonly property bool isGif: /\.gif$/i.test(shownPath)

    function _load(p) {
        if (!p || p === root.shownPath) return;
        if (root.transitioning) root._finish();          // a new change wins over a running one
        if (root.front === 0) root.pathB = p; else root.pathA = p;
    }
    function _begin() {
        let m = root.transition;
        if (m === "none" || !Motion.animate || root.duration <= 0) m = "none";
        else if (["zoom", "wipe", "circle", "dissolve", "blinds"].indexOf(m) >= 0 && !ShaderLibrary.usable("transition")) m = "fade";
        root.mode = m;
        if (m === "none") { root._finish(); return; }
        anim.stop();
        root.progress = 0;
        root.transitionStarted(m);
        anim.start();
    }
    function _finish() {
        anim.stop();
        root.front = root.front === 0 ? 1 : 0;
        root.progress = 1;
        if (root.front === 0) root.pathB = ""; else root.pathA = "";
        root.transitionFinished();
    }
    onPathChanged: if (pathA.length === 0 && pathB.length === 0) pathA = path; else _load(path)
    Component.onCompleted: if (path.length > 0 && pathA.length === 0) pathA = path

    NumberAnimation {
        id: anim
        target: root; property: "progress"
        from: 0; to: 1
        duration: Math.max(1, root.duration / Math.max(0.1, Motion.speed))
        easing.type: Easing.InOutCubic
        onFinished: root._finish()
    }

    Image {
        id: imgA
        visible: false
        width: root.width; height: root.height
        source: root.pathA.length > 0 ? "file://" + root.pathA : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true; cache: true
        sourceSize.width: root.sourceWidth; sourceSize.height: root.sourceHeight
        onStatusChanged: if (status === Image.Ready && root.front === 1 && root.pathA.length > 0) root._begin()
    }
    Image {
        id: imgB
        visible: false
        width: root.width; height: root.height
        source: root.pathB.length > 0 ? "file://" + root.pathB : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true; cache: true
        sourceSize.width: root.sourceWidth; sourceSize.height: root.sourceHeight
        onStatusChanged: if (status === Image.Ready && root.front === 0 && root.pathB.length > 0) root._begin()
    }

    // Steady state: the front picture, with parallax/depth when enabled.
    DepthImage {
        id: steady
        anchors.fill: parent
        visible: !root.transitioning && !(root.playGif && root.isGif)
        source: root.frontImage.source
        depthSource: root.parallax && root.depthPath.length > 0 ? "file://" + root.depthPath : ""
        offset: root.parallax ? root.offset : Qt.point(0, 0)
        strength: root.parallax ? 0.012 + 0.03 * Math.max(0, Math.min(1, root.parallaxStrength)) : 0
        sourceWidth: root.sourceWidth; sourceHeight: root.sourceHeight
    }
    readonly property bool trueDepth: steady.trueDepth

    AnimatedImage {
        anchors.fill: parent
        visible: root.playGif && root.isGif && !root.transitioning
        source: visible ? "file://" + root.shownPath : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true; cache: false
        playing: visible
    }

    WallpaperTransition {
        anchors.fill: parent
        visible: root.transitioning && root.mode !== "fade" && root.mode !== "slide"
        from: root.frontImage
        to: root.backImage
        progress: root.progress
        mode: root.mode
        direction: Qt.point(1, 0.25)
    }

    Item {
        anchors.fill: parent
        visible: root.transitioning && (root.mode === "fade" || root.mode === "slide")
        clip: true
        Image {
            width: parent.width; height: parent.height
            source: parent.visible ? root.frontImage.source : ""
            fillMode: Image.PreserveAspectCrop; cache: true
            sourceSize.width: root.sourceWidth; sourceSize.height: root.sourceHeight
            x: root.mode === "slide" ? -parent.width * 0.35 * root.progress : 0
            opacity: root.mode === "slide" ? 1 - 0.6 * root.progress : 1
        }
        Image {
            width: parent.width; height: parent.height
            source: parent.visible ? root.backImage.source : ""
            fillMode: Image.PreserveAspectCrop; cache: true
            sourceSize.width: root.sourceWidth; sourceSize.height: root.sourceHeight
            x: root.mode === "slide" ? parent.width * (1 - root.progress) : 0
            opacity: root.mode === "slide" ? 1 : root.progress
        }
    }
}
