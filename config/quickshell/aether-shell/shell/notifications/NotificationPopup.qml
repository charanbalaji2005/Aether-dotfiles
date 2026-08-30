import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import "../../theme"
import "../../services"

// Renders active notifications as stacked toasts in the top-right corner of
// the primary screen. Per-monitor popups are a future refinement (see
// PROGRESS.md) — for now this covers the common single/primary-monitor case.
Scope {
    id: root

    PanelWindow {
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true; right: true }
        margins { top: Metrics.spaceLg; right: Metrics.spaceLg }
        color: "transparent"
        implicitWidth: 340
        implicitHeight: list.implicitHeight

        ColumnLayout {
            id: list
            width: parent.width
            spacing: Metrics.spaceSm

            Repeater {
                model: NotificationService.activeNotifications

                delegate: Rectangle {
                    id: toast
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: content.implicitHeight + Metrics.spaceLg
                    radius: Metrics.radiusMd
                    color: Colors.withAlpha(Colors.glass, 0.94)
                    border.width: Metrics.borderWidth
                    border.color: toast.modelData.urgency === NotificationUrgency.Critical
                        ? Colors.danger
                        : Colors.borderStrong

                    ColumnLayout {
                        id: content
                        width: parent.width - Metrics.spaceLg
                        anchors.centerIn: parent
                        spacing: Metrics.spaceXs

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Metrics.spaceSm

                            Text {
                                text: toast.modelData.summary || toast.modelData.appName || "Notification"
                                color: Colors.textPrimary
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeMd
                                font.weight: Typography.weightSemibold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: "\u2715"
                                color: Colors.textMuted
                                font.pixelSize: Typography.sizeSm

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: NotificationService.dismiss(toast.modelData)
                                }
                            }
                        }

                        Text {
                            visible: text.length > 0
                            text: toast.modelData.body || ""
                            color: Colors.textSecondary
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeSm
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Metrics.spaceXs
                            visible: toast.modelData.actions && toast.modelData.actions.length > 0

                            Repeater {
                                model: toast.modelData.actions || []

                                delegate: Rectangle {
                                    required property var modelData
                                    implicitHeight: 26
                                    implicitWidth: actionLabel.implicitWidth + Metrics.spaceMd
                                    radius: Metrics.radiusPill
                                    color: Colors.withAlpha(Colors.accent, 0.16)

                                    Text {
                                        id: actionLabel
                                        anchors.centerIn: parent
                                        text: modelData.text || modelData.identifier || "Action"
                                        color: Colors.accent
                                        font.family: Typography.family
                                        font.pixelSize: Typography.sizeXs
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: NotificationService.invokeAction(toast.modelData, modelData)
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        onClicked: NotificationService.dismiss(toast.modelData)
                    }
                }
            }
        }
    }
}
