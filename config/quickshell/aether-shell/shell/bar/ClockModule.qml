import QtQuick
import "../../theme"
import "../../core"
import "../../components"

// Time and date. Ticks once per minute, aligned to the minute boundary,
// instead of every second. Click opens the dashboard (calendar + stats).
Capsule {
    id: root
    implicitWidth: label.implicitWidth + Metrics.spaceLg * 2
    onClicked: EventBus.dashboardRequested()

    property date now: new Date()
    readonly property string timeText: Qt.formatDateTime(now, Config.general.use24Hour ? "HH:mm" : "h:mm AP")
    readonly property string dateText: Qt.formatDateTime(now, "ddd d MMM")

    Timer {
        id: tick
        repeat: false
        running: true
        // Fire just after the next minute starts, then re-arm.
        interval: 60000 - (new Date().getSeconds() * 1000 + new Date().getMilliseconds()) + 50
        onTriggered: {
            root.now = new Date();
            interval = 60000 - (root.now.getSeconds() * 1000 + root.now.getMilliseconds()) + 50;
            restart();
        }
    }

    Row {
        id: label
        anchors.centerIn: parent
        spacing: Metrics.spaceSm

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.timeText
            color: Colors.textPrimary
            font.family: Typography.family
            font.pixelSize: Typography.sizeMd
            font.weight: Typography.weightBold
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 3; height: 3; radius: 1.5
            color: Colors.textMuted
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.dateText
            color: Colors.textSecondary
            font.family: Typography.family
            font.pixelSize: Typography.sizeSm
        }
    }
}
