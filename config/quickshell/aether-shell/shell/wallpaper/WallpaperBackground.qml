import QtQuick
import Quickshell
import "../../theme"
import "../../services"
import "../../core"

// Renders the active wallpaper on the desktop background layer across all monitors.
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: win
                required property var modelData
                screen: modelData

                WlLayer.layer: WlLayer.Background
                anchors { top: true; bottom: true; left: true; right: true }
                exclusionMode: ExclusionMode.Ignore
                color: Colors.bg0

                Item {
                    anchors.fill: parent

                    Image {
                        id: wallpaperImg
                        anchors.fill: parent
                        source: WallpaperService.currentWallpaper ? ("file://" + WallpaperService.currentWallpaper) : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        opacity: 1.0

                        Behavior on source {
                            // Fade transition on wallpaper change
                            SequentialAnimation {
                                NumberAnimation { target: wallpaperImg; property: "opacity"; to: 0.2; duration: Motion.reducedMotion ? 0 : 180; easing.type: Easing.OutQuad }
                                PropertyAction { target: wallpaperImg; property: "source" }
                                NumberAnimation { target: wallpaperImg; property: "opacity"; to: 1.0; duration: Motion.reducedMotion ? 0 : 250; easing.type: Easing.OutQuad }
                            }
                        }
                    }

                    // Optional user-configurable darkening overlay for text contrast
                    Rectangle {
                        anchors.fill: parent
                        color: Colors.withAlpha("#000000", WallpaperService.dimOverlay)
                        visible: WallpaperService.dimOverlay > 0
                    }
                }
            }
        }
    }
}
