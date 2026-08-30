import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../services"
import "../../components"

// Toggle from Hyprland with:
//   bind = SUPER, N, exec, qs -c aether-shell ipc call dashboard toggle
Scope {
    id: root

    PanelWindow {
        id: window
        visible: false
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        function toggleVisible() { visible = !visible; }

        MouseArea {
            anchors.fill: parent
            onClicked: window.visible = false
        }

        Rectangle {
            anchors.fill: parent
            color: Colors.withAlpha("#000000", 0.25)
        }

        Rectangle {
            id: card
            width: 340
            height: layout.implicitHeight + Metrics.spaceLg * 2
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: Metrics.barHeight + Metrics.spaceSm
            anchors.rightMargin: Metrics.spaceLg
            radius: Metrics.radiusLg
            color: Colors.withAlpha(Colors.glass, 0.95)
            border.width: Metrics.borderWidth
            border.color: Colors.borderStrong

            MouseArea {
                anchors.fill: parent // swallow clicks so the backdrop doesn't close the card
            }

            ColumnLayout {
                id: layout
                anchors.fill: parent
                anchors.margins: Metrics.spaceLg
                spacing: Metrics.spaceLg

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceSm

                    QuickToggle {
                        label: "DND"
                        active: NotificationService.doNotDisturb
                        onClicked: NotificationService.toggleDnd()
                    }
                    QuickToggle {
                        label: "Bluetooth"
                        visible: BluetoothService.available
                        active: BluetoothService.enabled
                        onClicked: BluetoothService.toggle()
                    }
                    QuickToggle {
                        label: "Mute"
                        visible: AudioService.available
                        active: AudioService.muted
                        onClicked: AudioService.toggleMute()
                    }
                }

                Rectangle { Layout.fillWidth: true; height: Metrics.borderWidth; color: Colors.border }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceSm

                    StatBar {
                        Layout.fillWidth: true
                        label: "CPU"
                        value: SystemMonitorService.cpuUsage
                        detail: Math.round(SystemMonitorService.cpuUsage * 100) + "%"
                    }
                    StatBar {
                        Layout.fillWidth: true
                        label: "Memory"
                        value: SystemMonitorService.memUsage
                        detail: SystemMonitorService.memUsedGb.toFixed(1) + " / " + SystemMonitorService.memTotalGb.toFixed(1) + " GB"
                    }
                    StatBar {
                        Layout.fillWidth: true
                        label: "Disk"
                        value: SystemMonitorService.diskUsage
                        detail: SystemMonitorService.diskUsedGb.toFixed(0) + " / " + SystemMonitorService.diskTotalGb.toFixed(0) + " GB"
                    }
                }

                Rectangle { Layout.fillWidth: true; height: Metrics.borderWidth; color: Colors.border }

                CalendarWidget { Layout.fillWidth: true }
            }
        }
    }

    IpcHandler {
        target: "dashboard"
        function toggle(): void { window.toggleVisible(); }
        function show(): void { window.visible = true; }
        function hide(): void { window.visible = false; }
    }
}
