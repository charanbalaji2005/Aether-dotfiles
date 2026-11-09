import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// Notification centre (SUPER+comma, or the bell in the bar).
// History is grouped by application (Settings → Notifications can turn
// grouping off), each entry and each group can be cleared, and Do Not
// Disturb is one click away. Opening the centre marks everything read.
Scope {
    id: root

    PopupPanel {
        id: panel
        layerNamespace: "aether-notifications"
        placement: "top-right"
        cardWidth: Metrics.notificationWidth
        cardHeight: Math.min(header.implicitHeight + Math.max(list.contentHeight, 120) + Metrics.spaceLg * 3, (screen ? screen.height : 900) - 120)

        onOpened: NotificationService.markRead()

        readonly property var groups: Config.notifications.groupByApp
            ? NotificationService.grouped()
            : [{ app: "", items: NotificationService.history.slice().reverse() }]

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Metrics.spaceLg
            spacing: Metrics.spaceMd

            ColumnLayout {
                id: header
                Layout.fillWidth: true
                spacing: Metrics.spaceSm

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Notifications"
                        color: Colors.textPrimary
                        font.family: Typography.family
                        font.weight: Typography.weightSemibold
                        font.pixelSize: Typography.sizeLg
                        Layout.fillWidth: true
                    }
                    IconButton {
                        visible: NotificationService.history.length > 0
                        icon: "trash"
                        onClicked: NotificationService.clearHistory()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceSm
                    AetherIcon { width: 15; height: 15; name: NotificationService.doNotDisturb ? "bell-off" : "bell"; color: Colors.textSecondary }
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
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Metrics.spaceMd
                model: panel.groups
                boundsBehavior: Flickable.StopAtBounds

                delegate: ColumnLayout {
                    id: group
                    required property var modelData
                    width: list.width
                    spacing: Metrics.spaceXs

                    RowLayout {
                        visible: group.modelData.app.length > 0
                        Layout.fillWidth: true
                        AppIcon {
                            iconName: group.modelData.appIcon || ""
                            visible: (group.modelData.appIcon || "").length > 0
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 16
                        }
                        SectionLabel { text: group.modelData.app + "  ·  " + group.modelData.items.length; Layout.fillWidth: true }
                        Text {
                            text: "Clear"
                            color: Colors.textMuted
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeXs
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: NotificationService.clearApp(group.modelData.app)
                            }
                        }
                    }

                    Repeater {
                        model: group.modelData.items
                        delegate: Rectangle {
                            id: entry
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: entryLayout.implicitHeight + Metrics.spaceMd
                            radius: Metrics.radiusMd
                            color: entryArea.containsMouse ? Colors.surfaceHover : Colors.withAlpha(Colors.surface, Colors.dark ? 0.55 : 0.85)
                            border.width: entry.modelData.urgency === "critical" ? Metrics.borderWidth : 0
                            border.color: Colors.danger

                            MouseArea { id: entryArea; anchors.fill: parent; hoverEnabled: true }

                            ColumnLayout {
                                id: entryLayout
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Metrics.spaceSm
                                anchors.leftMargin: Metrics.spaceMd
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
                                        text: Qt.formatDateTime(new Date(entry.modelData.time), Config.general.use24Hour ? "HH:mm" : "h:mm AP")
                                        color: Colors.textMuted
                                        font.family: Typography.family
                                        font.pixelSize: Typography.sizeXs
                                    }
                                    IconButton {
                                        icon: "close"
                                        iconSize: 10
                                        implicitWidth: 20; implicitHeight: 20
                                        opacity: entryArea.containsMouse || hovered ? 1 : 0
                                        onClicked: NotificationService.removeFromHistory(entry.modelData.id)
                                    }
                                }

                                Text {
                                    visible: text.length > 0
                                    text: entry.modelData.body
                                    textFormat: Text.StyledText
                                    color: Colors.textSecondary
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeXs
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    // On the ListView itself, not its zero-height contentItem.
                    parent: list
                    anchors.centerIn: parent
                    visible: NotificationService.history.length === 0
                    spacing: Metrics.spaceSm
                    AetherIcon {
                        Layout.alignment: Qt.AlignHCenter
                        width: 28; height: 28
                        name: NotificationService.doNotDisturb ? "bell-off" : "bell"
                        color: Colors.textMuted
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "You're all caught up"
                        color: Colors.textMuted
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeSm
                    }
                }
            }
        }
    }

    Connections {
        target: EventBus
        function onNotificationCenterRequested() { panel.toggle(); }
    }

    IpcHandler {
        target: "notifications"
        function toggle(): void { panel.toggle(); }
        function show(): void { panel.show(); }
        function hide(): void { panel.hide(); }
        function dnd(): void { NotificationService.toggleDnd(); }
        function clear(): void { NotificationService.clearHistory(); }
    }
}
