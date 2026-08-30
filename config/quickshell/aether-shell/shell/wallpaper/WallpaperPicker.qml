import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../services"
import "../../components"
import "../../core"

// Toggle from Hyprland with:
//   bind = SUPER, W, exec, qs -c aether-shell ipc call wallpaper toggle
//   bind = SUPER SHIFT, W, exec, aether wallpaper random
Scope {
    id: root

    PanelWindow {
        id: window
        visible: false
        focusable: true
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        property var results: []

        function open() {
            visible = true;
            searchField.text = "";
            results = WallpaperService.search("");
            searchField.forceActiveFocus();
        }

        function close() {
            visible = false;
        }

        function toggleVisible() {
            if (visible) close(); else open();
        }

        MouseArea {
            anchors.fill: parent
            onClicked: window.close()
        }

        Rectangle {
            anchors.fill: parent
            color: Colors.withAlpha("#000000", 0.45)
        }

        Rectangle {
            id: card
            width: Math.min(840, parent.width - 60)
            height: Math.min(600, parent.height - 80)
            anchors.centerIn: parent
            radius: Metrics.radiusLg
            color: Colors.bg0
            border.color: Colors.border
            border.width: 1

            MouseArea {
                anchors.fill: parent
                // absorb clicks inside the card
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Metrics.spaceLg
                spacing: Metrics.spaceMd

                // ── Header Row ──────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceMd

                    Text {
                        text: "Wallpapers"
                        color: Colors.textPrimary
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeLg
                        font.weight: Typography.weightBold
                    }

                    Text {
                        text: "(" + WallpaperService.wallpapers.length + " available)"
                        color: Colors.textMuted
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeSm
                    }

                    Item { Layout.fillWidth: true }

                    // Random Wallpaper Button
                    Rectangle {
                        width: randomRow.implicitWidth + 24
                        height: 32
                        radius: Metrics.radiusMd
                        color: randomArea.containsMouse ? Colors.accent : Colors.surfaceHover
                        border.color: Colors.accent
                        border.width: 1

                        RowLayout {
                            id: randomRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: "\u2684" // dice icon
                                color: randomArea.containsMouse ? Colors.bg0 : Colors.accent
                                font.pixelSize: Typography.sizeMd
                            }
                            Text {
                                text: "Random Wallpaper"
                                color: randomArea.containsMouse ? Colors.bg0 : Colors.textPrimary
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeSm
                                font.weight: Typography.weightMedium
                            }
                        }

                        MouseArea {
                            id: randomArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                WallpaperService.randomWallpaper();
                            }
                        }
                    }

                    // Close Button
                    Rectangle {
                        width: 32
                        height: 32
                        radius: Metrics.radiusMd
                        color: closeArea.containsMouse ? Colors.surfaceHover : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "\u2715"
                            color: Colors.textMuted
                            font.pixelSize: Typography.sizeSm
                        }

                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.close()
                        }
                    }
                }

                // ── Search Field ─────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 38
                    radius: Metrics.radiusMd
                    color: Colors.surface
                    border.color: searchField.activeFocus ? Colors.accent : Colors.border
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Metrics.spaceMd
                        anchors.rightMargin: Metrics.spaceMd
                        spacing: Metrics.spaceSm

                        Text {
                            text: "\uD83D\uDD0D"
                            color: Colors.textMuted
                            font.pixelSize: Typography.sizeSm
                        }

                        TextInput {
                            id: searchField
                            Layout.fillWidth: true
                            color: Colors.textPrimary
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeMd
                            clip: true

                            Text {
                                anchors.fill: parent
                                visible: !searchField.text && !searchField.activeFocus
                                text: "Search wallpapers\u2026 (Esc to close)"
                                color: Colors.textMuted
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeMd
                            }

                            onTextChanged: {
                                window.results = WallpaperService.search(text);
                            }

                            Keys.onEscapePressed: window.close()
                        }
                    }
                }

                // ── Grid of Wallpapers ──────────────────────────────────
                GridView {
                    id: grid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cellWidth: 240
                    cellHeight: 160
                    clip: true
                    model: window.results

                    delegate: Item {
                        width: grid.cellWidth
                        height: grid.cellHeight

                        property var item: modelData
                        property bool isActive: item && item.path === WallpaperService.currentWallpaper

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 6
                            radius: Metrics.radiusMd
                            color: Colors.surface
                            border.color: isActive ? Colors.accent : (itemArea.containsMouse ? Colors.textSecondary : Colors.border)
                            border.width: isActive ? 2 : 1
                            clip: true

                            // Thumbnail image
                            Image {
                                anchors.fill: parent
                                source: item.uri
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                opacity: itemArea.containsMouse ? 1.0 : (isActive ? 0.95 : 0.85)

                                Behavior on opacity {
                                    NumberAnimation { duration: 150 }
                                }
                            }

                            // Bottom gradient overlay for title
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 36
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "transparent" }
                                    GradientStop { position: 1.0; color: Colors.withAlpha("#000000", 0.85) }
                                }
                            }

                            // Title Label
                            Text {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 8
                                text: item.title
                                color: Colors.textPrimary
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeSm
                                font.weight: Typography.weightMedium
                                elide: Text.ElideRight
                            }

                            // Active Badge
                            Rectangle {
                                visible: isActive
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 6
                                width: activeText.implicitWidth + 12
                                height: 20
                                radius: 10
                                color: Colors.accent

                                Text {
                                    id: activeText
                                    anchors.centerIn: parent
                                    text: "Active"
                                    color: Colors.bg0
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeXs
                                    font.weight: Typography.weightBold
                                }
                            }

                            MouseArea {
                                id: itemArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    WallpaperService.setWallpaper(item.path);
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: grid.count === 0
                        text: "No wallpapers found matching query"
                        color: Colors.textMuted
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeMd
                    }
                }

                // ── Footer Status ───────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceMd

                    Text {
                        text: "Current: " + (WallpaperService.currentTitle || "None")
                        color: Colors.textSecondary
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeSm
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "Press Esc or click outside to dismiss"
                        color: Colors.textMuted
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeXs
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "wallpaper"
        function toggle(): void { window.toggleVisible(); }
        function show(): void { window.open(); }
        function hide(): void { window.close(); }
        function random(): void { WallpaperService.randomWallpaper(); }
        function next(): void { WallpaperService.nextWallpaper(); }
        function prev(): void { WallpaperService.prevWallpaper(); }
        function set(path: string): void { WallpaperService.setWallpaper(path); }
    }
}
