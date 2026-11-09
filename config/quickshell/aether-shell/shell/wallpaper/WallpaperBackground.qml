import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../services"
import "../../core"

// Desktop wallpaper on the background layer of every monitor.
//
//  * Per-display: Config.appearance.wallpapers[outputName] overrides the
//    global wallpaper for that output.
//  * Cross-fade between wallpapers (instant under reduced motion).
//  * Optional blur via MultiEffect. The effect source is a static image, so
//    the blurred texture is produced when the wallpaper changes — there is
//    no per-frame cost while the desktop is idle.
//  * Animated GIFs only play when enabled in Settings, on AC power, and
//    without reduced motion; otherwise the first frame is shown.
//  * Images are decoded at the screen's size (sourceSize), not their
//    native 8K resolution, to keep GPU memory reasonable.
//
// (Previously this used `WlLayer.layer` without importing Quickshell.Wayland,
// which is not a valid type — the background layer is set with
// WlrLayershell.layer below.)
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: win
                required property var modelData
                screen: modelData

                WlrLayershell.layer: WlrLayer.Background
                WlrLayershell.namespace: "aether-wallpaper"
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                color: Colors.bg0
                visible: Config.appearance.enableBackground

                readonly property string path: {
                    const map = Config.appearance.wallpapers || {};
                    const own = win.modelData ? map[win.modelData.name] : undefined;
                    return (own && own.length > 0) ? own : WallpaperService.currentWallpaper;
                }
                readonly property bool animate: WallpaperService.isAnimated(path)
                    && Config.appearance.animatedWallpapers
                    && !ShellState.onBattery
                    && !Motion.reducedMotion
                readonly property real blurAmount: Math.max(0, Math.min(1, Config.appearance.wallpaperBlur || 0))

                // Two layers so the old wallpaper stays visible while the new one fades in.
                property int front: 0
                property string shownA: ""
                property string shownB: ""

                onPathChanged: {
                    if (front === 0) { shownB = path; front = 1; }
                    else { shownA = path; front = 0; }
                }
                Component.onCompleted: shownA = path

                Item {
                    id: stage
                    anchors.fill: parent
                    visible: win.blurAmount === 0
                    layer.enabled: false

                    WallLayer { source: win.shownA; opacity: win.front === 0 ? 1 : 0; animate: win.animate; targetWidth: win.width; targetHeight: win.height }
                    WallLayer { source: win.shownB; opacity: win.front === 1 ? 1 : 0; animate: win.animate; targetWidth: win.width; targetHeight: win.height }
                }

                MultiEffect {
                    anchors.fill: parent
                    visible: win.blurAmount > 0
                    source: stage
                    blurEnabled: true
                    blur: win.blurAmount
                    blurMax: 64
                    autoPaddingEnabled: false
                }

                Rectangle {
                    anchors.fill: parent
                    color: "#000000"
                    opacity: WallpaperService.dimOverlay
                    visible: WallpaperService.dimOverlay > 0
                }

                component WallLayer: Item {
                    id: wl
                    property string source: ""
                    // Passed in explicitly rather than read from the enclosing window.
                    property bool animate: false
                    property int targetWidth: 1920
                    property int targetHeight: 1080
                    anchors.fill: parent
                    Behavior on opacity { NumberAnimation { duration: Motion.reducedMotion ? 0 : 450; easing.type: Easing.InOutQuad } }

                    Image {
                        anchors.fill: parent
                        visible: !wl.animate || !WallpaperService.isAnimated(wl.source)
                        source: wl.source.length > 0 && !(wl.animate && WallpaperService.isAnimated(wl.source)) ? "file://" + wl.source : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        sourceSize.width: wl.targetWidth
                        sourceSize.height: wl.targetHeight
                    }
                    AnimatedImage {
                        anchors.fill: parent
                        visible: wl.animate && WallpaperService.isAnimated(wl.source)
                        source: visible ? "file://" + wl.source : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        playing: visible && wl.opacity > 0
                    }
                }
            }
        }
    }
}
