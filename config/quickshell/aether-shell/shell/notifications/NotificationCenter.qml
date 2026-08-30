import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// Toggle from Hyprland with:
//   bind = SUPER, comma, exec, qs -c aether-shell ipc call notifications toggle
Scope {
    id: root

    PanelWindow {
        id: window
        visible: false
        focusable: true
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true; right: true }
        margins { top: Metrics.barHeight + Metrics.spaceSm; right: Metrics.spaceLg }
        color: "transparent"
        implicitWidth: 360
        implicitHeight: Math.min(500, list.contentHeight + 140)

        function toggleVisible() { visible = !visible; }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: Metrics.radiusLg
            color: Colors.withAlpha(Colors.glass, 0.96)
            border.width: Metrics.borderWidth
            border.color: Colors.borderStrong

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Metrics.spaceLg
                spacing: Metrics.spaceMd

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceSm

                    Text {
                        text: "Notifications"
                        color: Colors.textPrimary
                        font.family: Typography.family
                        font.weight: Typography.weightSemibold
                        font.pixelSize: Typography.sizeLg
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "Clear"
                        visible: NotificationService.history.length > 0
                        color: Colors.danger
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeSm

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NotificationService.clearHistory()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceSm

                    Text {
                        text: "Do Not Disturb"
                        color: Colors.textPrimary
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeMd
                        Layout.fillWidth: true
                    }
                    Switch {
                        checked: NotificationService.doNotDisturb
                        onToggled: NotificationService.toggleDnd()
                    }
                }

                Rectangle { Layout.fillWidth: true; height: Metrics.borderWidth; color: Colors.border }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Metrics.spaceSm
                    // Most recent first — history is stored oldest-to-newest.
                    model: NotificationService.history.slice().reverse()

                    delegate: Rectangle {
                        id: entry
                        required property var modelData
                        width: list.width
                        implicitHeight: entryLayout.implicitHeight + Metrics.spaceMd

                        radius: Metrics.radiusSm
                        color: Colors.withAlpha(Colors.textMuted, 0.06)
                        border.width: entry.modelData.urgency === "critical" ? Metrics.borderWidth : 0
                        border.color: Colors.danger

                        ColumnLayout {
                            id: entryLayout
                            anchors.fill: parent
                            anchors.margins: Metrics.spaceSm
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: entry.modelData.summary
                                    color: Colors.textPrimary
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeSm
                                    font.weight: Typography.weightMedium
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: Qt.formatDateTime(new Date(entry.modelData.time), "hh:mm")
                                    color: Colors.textMuted
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeXs
                                }
                            }

                            Text {
                                visible: text.length > 0
                                text: entry.modelData.body
                                color: Colors.textSecondary
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeXs
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        text: "No notifications yet"
                        color: Colors.textMuted
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeSm
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "notifications"
        function toggle(): void { window.toggleVisible(); }
        function show(): void { window.visible = true; }
        function hide(): void { window.visible = false; }
    }
}
