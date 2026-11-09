import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../core"
import "../../components"

// The AetherOS panel, one per monitor.
//
// Styles (Settings → Bar, or Config.bar.style):
//   full      edge-to-edge strip
//   floating  inset glass island with rounded ends (default)
//   dock      centred, only as wide as its content
// Position: top or bottom. The reserved (exclusive) zone always matches what
// is drawn, so windows never slide underneath the bar.
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: panel
                required property var modelData
                screen: modelData

                readonly property string style: Config.bar.style || "floating"
                readonly property bool atBottom: Config.bar.position === "bottom"
                readonly property int barH: Math.max(28, Config.bar.height)
                readonly property int gap: style === "full" ? 0 : Metrics.barMargin

                WlrLayershell.namespace: "aether-bar"
                WlrLayershell.layer: WlrLayer.Top

                anchors {
                    top: !panel.atBottom
                    bottom: panel.atBottom
                    left: panel.style !== "dock"
                    right: panel.style !== "dock"
                }

                // Dock: content width. Full/floating: anchored left+right.
                implicitWidth: panel.style === "dock" ? (dockLoader.item ? dockLoader.item.implicitWidth : 400) + Metrics.spaceMd * 2 : 0
                implicitHeight: barH + gap
                exclusiveZone: barH + gap
                color: "transparent"

                // ── Background ──────────────────────────────────────────
                GlassPanel {
                    id: surface
                    anchors.fill: parent
                    anchors.topMargin: panel.atBottom ? 0 : panel.gap
                    anchors.bottomMargin: panel.atBottom ? panel.gap : 0
                    anchors.leftMargin: panel.style === "floating" ? panel.gap : 0
                    anchors.rightMargin: panel.style === "floating" ? panel.gap : 0
                    tintOpacity: Config.appearance.barOpacity
                    radius: panel.style === "full" ? 0 : Math.min(height / 2, Metrics.radiusLg)
                    border.width: panel.style === "full" ? 0 : Metrics.borderWidth
                    sheen: panel.style !== "full"

                    // Hairline separator for the edge-to-edge style.
                    Rectangle {
                        visible: panel.style === "full"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: panel.atBottom ? undefined : parent.bottom
                        anchors.top: panel.atBottom ? parent.top : undefined
                        height: 1
                        color: Colors.withAlpha(Colors.border, 0.8)
                    }
                }

                // ── Full / floating layout: left · centre · right ───────
                // Loaders keep the inactive layout from instantiating at all.
                Loader {
                    anchors.fill: surface
                    anchors.leftMargin: Metrics.spaceSm
                    anchors.rightMargin: Metrics.spaceSm
                    active: panel.style !== "dock"
                    sourceComponent: Item {
                        id: wide

                        RowLayout {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Metrics.spaceSm

                            LauncherButton { id: launcherBtn }
                            WorkspacesModule { id: wsModule }
                            ActiveWindowModule {
                                // Never run into the centred clock.
                                maxWidth: Math.max(0, wide.width / 2 - clock.width / 2 - launcherBtn.width - wsModule.width - Metrics.spaceSm * 2 - Metrics.spaceXl)
                            }
                        }

                        ClockModule {
                            id: clock
                            anchors.centerIn: parent
                        }

                        RowLayout {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Metrics.spaceXs

                            SystemStatsModule {}
                            NetSpeedModule {}
                            TrayModule {}
                            MediaModule {}
                            BluetoothModule {}
                            NetworkModule {}
                            AudioModule {}
                            MicModule {}
                            BatteryModule {}
                            NotificationModule {}
                            QuickSettingsButton {}
                        }
                    }
                }

                // ── Dock layout: one centred row ───────────────────────
                Loader {
                    id: dockLoader
                    anchors.centerIn: surface
                    active: panel.style === "dock"
                    sourceComponent: RowLayout {
                        spacing: Metrics.spaceXs

                        LauncherButton {}
                        WorkspacesModule {}
                        ClockModule {}
                        SystemStatsModule {}
                        TrayModule {}
                        NetworkModule {}
                        AudioModule {}
                        MicModule {}
                        BatteryModule {}
                        NotificationModule {}
                        QuickSettingsButton {}
                    }
                }
            }
        }
    }
}
