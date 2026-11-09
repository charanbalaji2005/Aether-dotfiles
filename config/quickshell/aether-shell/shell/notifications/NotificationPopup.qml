import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// Notification toasts, stacked under the bar on the focused monitor's side
// (top-right; bottom-right when the bar is at the bottom). Each toast slides
// and fades in, shows the app icon or image, an urgency accent strip, and
// any actions the app offers. Click a toast to dismiss it.
Scope {
    id: root

    // Notifications that have already played their entrance animation.
    property var seen: []

    PanelWindow {
        id: window
        visible: NotificationService.activeNotifications.length > 0
        screen: ShellState.activeScreen ? ShellState.activeScreen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
        WlrLayershell.namespace: "aether-toasts"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Normal
        readonly property bool atBottom: Config.bar.position === "bottom"
        anchors { top: !atBottom; bottom: atBottom; right: true }
        margins { top: Metrics.spaceSm; bottom: Metrics.spaceSm; right: Metrics.spaceLg }
        color: "transparent"
        implicitWidth: Metrics.toastWidth
        implicitHeight: Math.max(1, stack.implicitHeight)

        ColumnLayout {
            id: stack
            width: parent.width
            spacing: Metrics.spaceSm

            Repeater {
                model: NotificationService.activeNotifications

                delegate: Item {
                    id: toast
                    required property var modelData
                    readonly property bool critical: modelData.urgency === NotificationUrgency.Critical
                    readonly property string imageSource: modelData.image || ""
                    readonly property string appIcon: modelData.appIcon || ""

                    Layout.fillWidth: true
                    implicitHeight: card.height

                    // Entrance: slide in from the screen edge + fade.
                    // The model array is reassigned whenever any toast comes or
                    // goes, which recreates every delegate. Only notifications
                    // not seen before animate in; the rest appear in place.
                    readonly property bool isNew: root.seen.indexOf(modelData) < 0
                    property real enter: isNew ? 0 : 1
                    Component.onCompleted: {
                        if (isNew) {
                            root.seen = root.seen.concat([modelData]).slice(-64);
                            enter = 1;
                        }
                    }
                    Behavior on enter { NumberAnimation { duration: Motion.panel; easing.type: Motion.easeSpring } }

                    GlassPanel {
                        id: card
                        width: parent.width
                        height: content.implicitHeight + Metrics.spaceMd * 2
                        radius: Metrics.radiusLg
                        tintOpacity: Math.max(0.88, Colors.glassOpacity)
                        border.color: toast.critical ? Colors.danger : Colors.withAlpha(Colors.borderStrong, 0.8)
                        opacity: toast.enter
                        x: (1 - toast.enter) * (Motion.reducedMotion ? 0 : 40)

                        // Urgency accent strip.
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: Metrics.spaceSm
                            width: 3
                            radius: 1.5
                            color: toast.critical ? Colors.danger : Colors.accent
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NotificationService.dismiss(toast.modelData)
                        }

                        RowLayout {
                            id: content
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Metrics.spaceMd
                            anchors.leftMargin: Metrics.spaceLg
                            spacing: Metrics.spaceMd

                            Item {
                                Layout.alignment: Qt.AlignTop
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                visible: toast.imageSource.length > 0 || toast.appIcon.length > 0 || toast.modelData.local === true

                                Image {
                                    anchors.fill: parent
                                    visible: toast.imageSource.length > 0
                                    source: toast.imageSource
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize.width: 72
                                    sourceSize.height: 72
                                    asynchronous: true
                                    layer.enabled: false
                                }
                                AppIcon {
                                    anchors.fill: parent
                                    visible: toast.imageSource.length === 0 && toast.appIcon.length > 0
                                    iconName: toast.appIcon
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    visible: toast.modelData.local === true
                                    radius: 18
                                    color: Colors.accentSoft
                                    AetherIcon { anchors.centerIn: parent; width: 18; height: 18; name: "bell"; color: Colors.accent }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Metrics.spaceXxs

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Metrics.spaceSm
                                    Text {
                                        text: toast.modelData.appName || ""
                                        visible: text.length > 0
                                        color: Colors.textMuted
                                        font.family: Typography.family
                                        font.pixelSize: Typography.sizeXs
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Item { Layout.fillWidth: true; visible: !(toast.modelData.appName) }
                                    IconButton {
                                        icon: "close"
                                        iconSize: 10
                                        implicitWidth: 20; implicitHeight: 20
                                        onClicked: NotificationService.dismiss(toast.modelData)
                                    }
                                }

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
                                    visible: text.length > 0
                                    text: toast.modelData.body || ""
                                    textFormat: Text.StyledText
                                    color: Colors.textSecondary
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeSm
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                    maximumLineCount: 4
                                    elide: Text.ElideRight
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    Layout.topMargin: Metrics.spaceXs
                                    spacing: Metrics.spaceXs
                                    visible: toast.modelData.actions && toast.modelData.actions.length > 0

                                    Repeater {
                                        model: toast.modelData.actions || []

                                        delegate: Rectangle {
                                            id: actionBtn
                                            required property var modelData
                                            implicitHeight: 28
                                            implicitWidth: actionLabel.implicitWidth + Metrics.spaceLg
                                            radius: Metrics.radiusPill
                                            color: actionArea.containsMouse ? Colors.accent : Colors.accentSoft

                                            Text {
                                                id: actionLabel
                                                anchors.centerIn: parent
                                                text: actionBtn.modelData.text || actionBtn.modelData.identifier || "Action"
                                                color: actionArea.containsMouse ? Colors.onAccent : Colors.accent
                                                font.family: Typography.family
                                                font.pixelSize: Typography.sizeXs
                                                font.weight: Typography.weightMedium
                                            }

                                            MouseArea {
                                                id: actionArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: NotificationService.invokeAction(toast.modelData, actionBtn.modelData)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
