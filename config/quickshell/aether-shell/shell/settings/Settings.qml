import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// Toggle from Hyprland with:
//   bind = SUPER, I, exec, qs -c aether-shell ipc call settings toggle
Scope {
    id: root

    readonly property var accentPresets: ["#7C9CFF", "#B48CFF", "#38BDF8", "#4ADE80", "#FBBF24", "#F87171"]
    readonly property var sections: [
        { id: "appearance", label: "Appearance" },
        { id: "bar", label: "Bar" },
        { id: "about", label: "About" }
    ]

    PanelWindow {
        id: window
        visible: false
        focusable: true
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        property string activeSection: "appearance"

        function toggleVisible() { visible = !visible; }

        MouseArea {
            anchors.fill: parent
            onClicked: window.visible = false
        }

        Rectangle {
            anchors.fill: parent
            color: Colors.withAlpha("#000000", 0.35)
        }

        Rectangle {
            id: card
            width: Math.min(640, parent.width - 120)
            height: Math.min(480, parent.height - 160)
            anchors.centerIn: parent
            radius: Metrics.radiusLg
            color: Colors.withAlpha(Colors.glass, 0.96)
            border.width: Metrics.borderWidth
            border.color: Colors.borderStrong

            MouseArea {
                anchors.fill: parent // swallow clicks so the backdrop doesn't close the card
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // ── Sidebar ──────────────────────────────────────────────
                ColumnLayout {
                    Layout.preferredWidth: 160
                    Layout.fillHeight: true
                    Layout.margins: Metrics.spaceMd
                    spacing: Metrics.spaceXs

                    Repeater {
                        model: root.sections

                        delegate: Rectangle {
                            id: navItem
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 36
                            radius: Metrics.radiusSm
                            color: window.activeSection === navItem.modelData.id
                                ? Colors.withAlpha(Colors.accent, 0.18) : "transparent"

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Metrics.spaceMd
                                anchors.verticalCenter: parent.verticalCenter
                                text: navItem.modelData.label
                                color: window.activeSection === navItem.modelData.id ? Colors.accent : Colors.textSecondary
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeSm
                                font.weight: Typography.weightMedium
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: window.activeSection = navItem.modelData.id
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                Rectangle { Layout.preferredWidth: Metrics.borderWidth; Layout.fillHeight: true; color: Colors.border }

                // ── Appearance ───────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: Metrics.spaceLg
                    spacing: Metrics.spaceLg
                    visible: window.activeSection === "appearance"

                    Text {
                        text: "Appearance"
                        color: Colors.textPrimary
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeLg
                        font.weight: Typography.weightSemibold
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Accent color"
                                color: Colors.textPrimary
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeMd
                                Layout.fillWidth: true
                            }
                            Row {
                                spacing: Metrics.spaceSm
                                Repeater {
                                    model: root.accentPresets
                                    delegate: ColorSwatch {
                                        required property string modelData
                                        swatchColor: modelData
                                        selected: Config.appearance.accent.toLowerCase() === modelData.toLowerCase()
                                        onClicked: Config.appearance.accent = modelData
                                    }
                                }
                            }
                        }
                        Text {
                            text: "Used across the bar, launcher, and dashboard."
                            color: Colors.textMuted
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeXs
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Bar opacity"
                            color: Colors.textPrimary
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeMd
                            Layout.fillWidth: true
                        }
                        Text {
                            text: Math.round(Config.appearance.barOpacity * 100) + "%"
                            color: Colors.textMuted
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeXs
                        }
                        Slider {
                            Layout.preferredWidth: 140
                            Layout.leftMargin: Metrics.spaceSm
                            from: 0.3
                            to: 1.0
                            value: Config.appearance.barOpacity
                            onMoved: function(v) { Config.appearance.barOpacity = v; }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Reduced motion"
                            color: Colors.textPrimary
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeMd
                            Layout.fillWidth: true
                        }
                        Switch {
                            checked: Config.general.reducedMotion
                            onToggled: function(v) { Config.general.reducedMotion = v; }
                        }
                    }

                    // ── Wallpaper ──────────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Metrics.spaceSm

                        Text {
                            text: "Wallpaper"
                            color: Colors.textPrimary
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeMd
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Metrics.spaceMd

                            // Thumbnail preview
                            Rectangle {
                                width: 120
                                height: 68
                                radius: Metrics.radiusMd
                                color: Colors.surface
                                border.color: Colors.border
                                border.width: 1
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    source: WallpaperService.currentWallpaper ? ("file://" + WallpaperService.currentWallpaper) : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: WallpaperService.currentTitle || "No wallpaper active"
                                    color: Colors.textPrimary
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeSm
                                    font.weight: Typography.weightMedium
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: (WallpaperService.wallpapers.length) + " wallpapers available ($mod + W)"
                                    color: Colors.textMuted
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeXs
                                }

                                RowLayout {
                                    spacing: Metrics.spaceSm

                                    Rectangle {
                                        width: changeWpText.implicitWidth + 16
                                        height: 28
                                        radius: Metrics.radiusSm
                                        color: changeWpArea.containsMouse ? Colors.accent : Colors.surfaceHover
                                        border.color: Colors.accent
                                        border.width: 1

                                        Text {
                                            id: changeWpText
                                            anchors.centerIn: parent
                                            text: "Browse Wallpapers"
                                            color: changeWpArea.containsMouse ? Colors.bg0 : Colors.accent
                                            font.family: Typography.family
                                            font.pixelSize: Typography.sizeXs
                                            font.weight: Typography.weightMedium
                                        }

                                        MouseArea {
                                            id: changeWpArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                WallpaperService.search("");
                                                // open wallpaper picker
                                                Quickshell.execDetached(["qs", "-c", "aether-shell", "ipc", "call", "wallpaper", "show"]);
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: randWpText.implicitWidth + 16
                                        height: 28
                                        radius: Metrics.radiusSm
                                        color: randWpArea.containsMouse ? Colors.surfaceHover : Colors.surface
                                        border.color: Colors.border
                                        border.width: 1

                                        Text {
                                            id: randWpText
                                            anchors.centerIn: parent
                                            text: "\u2684 Random"
                                            color: Colors.textPrimary
                                            font.family: Typography.family
                                            font.pixelSize: Typography.sizeXs
                                        }

                                        MouseArea {
                                            id: randWpArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: WallpaperService.randomWallpaper()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // ── Bar ──────────────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: Metrics.spaceLg
                    spacing: Metrics.spaceMd
                    visible: window.activeSection === "bar"

                    Text {
                        text: "Bar"
                        color: Colors.textPrimary
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeLg
                        font.weight: Typography.weightSemibold
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Position"
                            color: Colors.textPrimary
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeMd
                            Layout.fillWidth: true
                        }
                        Row {
                            spacing: Metrics.spaceSm
                            Repeater {
                                model: ["top", "bottom"]
                                delegate: Rectangle {
                                    id: posOption
                                    required property string modelData
                                    implicitWidth: 64
                                    implicitHeight: 28
                                    radius: Metrics.radiusPill
                                    color: Config.bar.position === posOption.modelData
                                        ? Colors.accent : Colors.withAlpha(Colors.textMuted, 0.15)

                                    Text {
                                        anchors.centerIn: parent
                                        text: posOption.modelData
                                        color: Config.bar.position === posOption.modelData ? Colors.bg0 : Colors.textSecondary
                                        font.family: Typography.family
                                        font.pixelSize: Typography.sizeXs
                                        font.capitalization: Font.Capitalize
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Config.bar.position = posOption.modelData
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Height"
                            color: Colors.textPrimary
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeMd
                            Layout.fillWidth: true
                        }
                        Text {
                            text: Config.bar.height + "px"
                            color: Colors.textMuted
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeXs
                        }
                        Slider {
                            Layout.preferredWidth: 140
                            Layout.leftMargin: Metrics.spaceSm
                            from: 28
                            to: 56
                            value: Config.bar.height
                            onMoved: function(v) { Config.bar.height = Math.round(v); }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: Metrics.borderWidth; color: Colors.border }

                    Repeater {
                        model: [
                            { label: "Network module", key: "showNetwork" },
                            { label: "Audio module", key: "showAudio" },
                            { label: "Battery module", key: "showBattery" },
                            { label: "Media module", key: "showMedia" },
                            { label: "Bluetooth module", key: "showBluetooth" }
                        ]

                        delegate: RowLayout {
                            id: moduleRow
                            required property var modelData
                            Layout.fillWidth: true

                            Text {
                                text: moduleRow.modelData.label
                                color: Colors.textPrimary
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeMd
                                Layout.fillWidth: true
                            }
                            Switch {
                                checked: moduleRow.modelData.key === "showNetwork" ? Config.bar.showNetwork
                                    : moduleRow.modelData.key === "showAudio" ? Config.bar.showAudio
                                    : moduleRow.modelData.key === "showBattery" ? Config.bar.showBattery
                                    : moduleRow.modelData.key === "showMedia" ? Config.bar.showMedia
                                    : Config.bar.showBluetooth
                                onToggled: function(v) {
                                    if (moduleRow.modelData.key === "showNetwork") Config.bar.showNetwork = v;
                                    else if (moduleRow.modelData.key === "showAudio") Config.bar.showAudio = v;
                                    else if (moduleRow.modelData.key === "showBattery") Config.bar.showBattery = v;
                                    else if (moduleRow.modelData.key === "showMedia") Config.bar.showMedia = v;
                                    else Config.bar.showBluetooth = v;
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // ── About ────────────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: Metrics.spaceLg
                    spacing: Metrics.spaceSm
                    visible: window.activeSection === "about"

                    Text {
                        text: "About"
                        color: Colors.textPrimary
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeLg
                        font.weight: Typography.weightSemibold
                    }

                    Text {
                        text: "AetherOS Shell — an independently implemented Hyprland desktop shell built on Quickshell."
                        color: Colors.textSecondary
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeSm
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Rectangle { Layout.fillWidth: true; height: Metrics.borderWidth; color: Colors.border; Layout.topMargin: Metrics.spaceSm; Layout.bottomMargin: Metrics.spaceSm }

                    Text {
                        text: "Service status"
                        color: Colors.textMuted
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeXs
                        font.weight: Typography.weightSemibold
                    }

                    Repeater {
                        model: [
                            { label: "Hyprland", available: HyprlandService.available },
                            { label: "Audio (PipeWire)", available: AudioService.available },
                            { label: "Battery (UPower)", available: PowerService.available },
                            { label: "Network (NetworkManager)", available: NetworkService.available },
                            { label: "Bluetooth (BlueZ)", available: BluetoothService.available },
                            { label: "Media (MPRIS)", available: MediaService.available },
                            { label: "Clipboard (cliphist)", available: ClipboardService.available },
                            { label: "Screenshots (grim)", available: ScreenshotService.available }
                        ]

                        delegate: RowLayout {
                            id: statusRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Metrics.spaceSm

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: statusRow.modelData.available ? Colors.success : Colors.textMuted
                            }
                            Text {
                                text: statusRow.modelData.label
                                color: Colors.textSecondary
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeSm
                                Layout.fillWidth: true
                            }
                            Text {
                                text: statusRow.modelData.available ? "available" : "unavailable"
                                color: statusRow.modelData.available ? Colors.success : Colors.textMuted
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeXs
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { window.toggleVisible(); }
        function show(): void { window.visible = true; }
        function hide(): void { window.visible = false; }
    }
}
