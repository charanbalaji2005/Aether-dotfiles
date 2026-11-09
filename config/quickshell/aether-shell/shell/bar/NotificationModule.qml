import QtQuick
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// Notification indicator: bell with an unread badge, crossed bell while Do
// Not Disturb is on. Click opens the notification centre; right-click
// toggles Do Not Disturb.
Capsule {
    id: root
    visible: Config.bar.showNotifications
    implicitWidth: implicitHeight
    onClicked: EventBus.notificationCenterRequested()
    onRightClicked: NotificationService.toggleDnd()

    AetherIcon {
        id: bell
        anchors.centerIn: parent
        width: Metrics.iconSm + 1; height: Metrics.iconSm + 1
        name: NotificationService.doNotDisturb ? "bell-off" : "bell"
        color: NotificationService.doNotDisturb ? Colors.textMuted : Colors.textPrimary
    }

    Rectangle {
        id: badge
        visible: NotificationService.unread > 0 && !NotificationService.doNotDisturb
        anchors.horizontalCenter: bell.right
        anchors.verticalCenter: bell.top
        height: 13
        width: Math.max(height, countText.implicitWidth + 6)
        radius: height / 2
        color: Colors.accent
        border.width: 1
        border.color: Colors.bg0

        Text {
            id: countText
            anchors.centerIn: parent
            text: NotificationService.unread > 9 ? "9+" : String(NotificationService.unread)
            color: Colors.onAccent
            font.family: Typography.family
            font.pixelSize: 8
            font.weight: Typography.weightBold
        }

        // A small pop when the count goes up.
        scale: 1
        Behavior on scale { enabled: !Motion.reducedMotion; NumberAnimation { duration: Motion.fast; easing.type: Motion.easeEmphasized } }
        Connections {
            target: NotificationService
            function onUnreadChanged() {
                if (Motion.reducedMotion || NotificationService.unread === 0) return;
                badge.scale = 1.35;
                popBack.restart();
            }
        }
        Timer { id: popBack; interval: 120; onTriggered: badge.scale = 1 }
    }
}
