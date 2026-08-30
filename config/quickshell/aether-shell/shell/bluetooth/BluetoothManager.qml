import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// Toggle from Hyprland with:
//   bind = SUPER, B, exec, qs -c aether-shell ipc call bluetooth toggle
//
// Discovery/pairing actions here rely on BluetoothService's best-effort API
// guesses (see that file's comments) — connect/disconnect are the two
// pieces confirmed against Quickshell's documented Bluetooth module; scan/
// pair/forget are implemented but unverified. Buttons for those fail
// silently (logged) rather than crashing if the underlying method name is
// wrong on your Quickshell version.
Scope {
    id: root

    PanelWindow {
        id: window
        visible: false
        focusable: true
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
            color: Colors.withAlpha("#000000", 0.35)
        }

        Rectangle {
            width: Math.min(420, parent.width - 80)
            height: Math.min(480, parent.height - 160)
            anchors.centerIn: parent
            radius: Metrics.radiusLg
            color: Colors.withAlpha(Colors.glass, 0.96)
            border.width: Metrics.borderWidth
            border.color: Colors.borderStrong

            MouseArea {
                anchors.fill: parent // swallow clicks so the backdrop doesn't close the card
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Metrics.spaceLg
                spacing: Metrics.spaceMd

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceSm

                    Text {
                        text: "Bluetooth"
                        color: Colors.textPrimary
                        font.family: Typography.family
                        font.weight: Typography.weightSemibold
                        font.pixelSize: Typography.sizeLg
                        Layout.fillWidth: true
                    }

                    Switch {
                        checked: BluetoothService.enabled
                        onToggled: BluetoothService.toggle()
                    }
                }

                Text {
                    visible: !BluetoothService.available
                    text: "No Bluetooth adapter detected."
                    color: Colors.textMuted
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeSm
                }

                RowLayout {
                    visible: BluetoothService.available && BluetoothService.enabled
                    Layout.fillWidth: true

                    Text {
                        text: BluetoothService.discovering ? "Scanning for devices\u2026" : "Nearby devices"
                        color: Colors.textMuted
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeXs
                        Layout.fillWidth: true
                    }

                    Text {
                        text: BluetoothService.discovering ? "Stop scan" : "Scan"
                        color: Colors.accent
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeSm

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: BluetoothService.discovering
                                ? BluetoothService.stopDiscovery()
                                : BluetoothService.startDiscovery()
                        }
                    }
                }

                Rectangle {
                    visible: BluetoothService.available && BluetoothService.enabled
                    Layout.fillWidth: true
                    height: Metrics.borderWidth
                    color: Colors.border
                }

                ListView {
                    id: list
                    visible: BluetoothService.available && BluetoothService.enabled
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: BluetoothService.enabled ? BluetoothService.devices : null

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        width: list.width
                        implicitHeight: 56
                        radius: Metrics.radiusSm
                        color: Colors.withAlpha(Colors.textMuted, 0.06)

                        readonly property bool connected: row.modelData.state === BluetoothDeviceState.Connected
                        readonly property bool paired: row.modelData.paired === true

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Metrics.spaceSm
                            spacing: Metrics.spaceMd

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: row.connected ? Colors.success : Colors.withAlpha(Colors.textMuted, 0.5)
                            }

                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true

                                Text {
                                    text: row.modelData.name || "Unknown device"
                                    color: Colors.textPrimary
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeSm
                                    font.weight: Typography.weightMedium
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: [
                                        row.connected ? "Connected" : (row.paired ? "Paired" : "Not paired"),
                                        (row.modelData.batteryAvailable === true) ? Math.round(row.modelData.battery * 100) + "%" : ""
                                    ].filter(function(s) { return s.length > 0; }).join(" \u00b7 ")
                                    color: Colors.textMuted
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeXs
                                }
                            }

                            Text {
                                text: row.paired ? (row.connected ? "Disconnect" : "Connect") : "Pair"
                                color: Colors.accent
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeXs

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!row.paired) {
                                            BluetoothService.pairDevice(row.modelData);
                                        } else if (row.connected) {
                                            BluetoothService.disconnectDevice(row.modelData);
                                        } else {
                                            BluetoothService.connectDevice(row.modelData);
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: row.paired
                                text: "Forget"
                                color: Colors.danger
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeXs

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: BluetoothService.forgetDevice(row.modelData)
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        text: "No devices found yet. Try Scan."
                        color: Colors.textMuted
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeSm
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "bluetooth"
        function toggle(): void { window.toggleVisible(); }
        function show(): void { window.visible = true; }
        function hide(): void { window.visible = false; }
    }

    Connections {
        target: EventBus
        function onBluetoothManagerRequested() { window.visible = true; }
    }
}
