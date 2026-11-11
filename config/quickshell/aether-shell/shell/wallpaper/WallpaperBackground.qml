import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../theme"
import "../../services"
import "../../core"
import "../../graphics"
import "../../animation"

// The desktop wallpaper on the background layer of every monitor.
//
// Rendering and transitions live in graphics/WallpaperStage.qml (pure Qt
// Quick, runtime-tested); this file adds the window per monitor, the
// services, pointer tracking, blur, dim and the ambient layers.
//
// While idle:
//   * parallax (opt-in): the pointer position, eased by a gentle spring,
//     shifts the picture; with a depth map (<name>.depth.png next to the
//     image) near pixels move more than far ones — real depth, see
//     graphics/DepthImage.qml. The background layer only receives pointer
//     motion when nothing covers it, so it settles when you work.
//   * ambient layer (opt-in): particles (stars/snow/rain/dust) or aurora,
//     only in the tier that allows them and paused under fullscreen apps.
//   * blur (static): rendered once per wallpaper, not per frame.
//   * GIFs play only when enabled, on AC power, without reduced motion.
// Video wallpapers are drawn by mpvpaper (VideoWallpaperService) above
// this layer; this static image remains underneath as the fallback.
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

                // Precedence: this workspace's wallpaper (Settings → Workspaces),
                // then this monitor's, then the global one. Switching to a
                // workspace with its own wallpaper plays the normal transition.
                readonly property var hyprMonitor: Hyprland.monitorFor(win.modelData)
                readonly property int activeWs: hyprMonitor && hyprMonitor.activeWorkspace ? hyprMonitor.activeWorkspace.id : -1
                readonly property string path: {
                    const perWs = (Config.wallpaper.perWorkspace || {})[String(win.activeWs)];
                    if (perWs && perWs.length > 0) return perWs;
                    const map = Config.appearance.wallpapers || {};
                    const own = win.modelData ? map[win.modelData.name] : undefined;
                    return (own && own.length > 0) ? own : WallpaperService.currentWallpaper;
                }
                readonly property string mode: Config.wallpaper.mode || "image"
                readonly property bool animateGif: WallpaperService.isAnimated(path)
                    && Config.appearance.animatedWallpapers && !ShellState.onBattery && !Motion.reducedMotion
                readonly property real blurAmount: Math.max(0, Math.min(1, Config.appearance.wallpaperBlur || 0))
                readonly property int tw: Math.max(1, win.width)
                readonly property int th: Math.max(1, win.height)

                // ── Pointer parallax ──────────────────────────────────
                HoverHandler { id: pointer; enabled: Effects.parallax }
                SpringValue { id: px; preset: "gentle"; target: pointer.hovered ? (pointer.point.position.x / Math.max(1, win.width)) * 2 - 1 : 0 }
                SpringValue { id: py; preset: "gentle"; target: pointer.hovered ? (pointer.point.position.y / Math.max(1, win.height)) * 2 - 1 : 0 }

                Item {
                    id: stage
                    anchors.fill: parent
                    visible: win.blurAmount === 0

                    // Generated wallpapers from the palette (no image needed).
                    Rectangle {
                        anchors.fill: parent
                        visible: win.mode === "gradient"
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.0; color: Colors.mix(Colors.bg0, Colors.accent, 0.28) }
                            GradientStop { position: 0.55; color: Colors.bg0 }
                            GradientStop { position: 1.0; color: Colors.mix(Colors.bg0, Colors.accentAlt, 0.22) }
                        }
                    }
                    Loader {
                        anchors.fill: parent
                        active: win.mode === "aurora"
                        sourceComponent: AuroraSurface {
                            strength: Colors.dark ? 0.55 : 0.35
                            running: Effects.ambient && !WindowService.fullscreenActive
                        }
                    }

                    WallpaperStage {
                        id: wall
                        visible: win.mode === "image"
                        anchors.fill: parent
                        path: win.path
                        transition: WallpaperService.activeTransition
                        duration: Config.wallpaper.transitionDuration
                        depthPath: WallpaperService.depthFor(win.path)
                        parallax: Effects.parallax
                        offset: Qt.point(px.value, py.value)
                        parallaxStrength: Config.wallpaper.parallaxStrength
                        playGif: win.animateGif
                        sourceWidth: win.tw; sourceHeight: win.th
                    }

                    // Ambient layer.
                    Loader {
                        anchors.fill: parent
                        active: Effects.particles && ["stars", "snow", "rain", "dust"].indexOf(Config.wallpaper.ambient) >= 0
                        sourceComponent: ParticleField {
                            kind: Config.wallpaper.ambient
                            density: Config.wallpaper.ambientDensity
                            running: !WindowService.fullscreenActive
                        }
                    }
                    Loader {
                        anchors.fill: parent
                        active: Config.wallpaper.ambient === "aurora" && Effects.ambient && !Effects.eco
                        sourceComponent: AuroraSurface {
                            opacity: 0.35 * Math.max(0.2, Config.wallpaper.ambientDensity)
                            base: "#000000"
                            running: !WindowService.fullscreenActive
                        }
                    }
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
            }
        }
    }
}
