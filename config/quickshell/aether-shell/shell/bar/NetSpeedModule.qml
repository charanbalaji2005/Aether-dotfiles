import QtQuick
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// Download / upload throughput of the default-route interface.
// Off by default (Settings → Bar → Network speed).
Capsule {
    id: root
    visible: Config.bar.showNetSpeed && SystemMonitorService.netRxBps >= 0
    implicitWidth: row.implicitWidth + Metrics.spaceMd * 2
    onClicked: EventBus.dashboardRequested()

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Metrics.spaceSm

        Repeater {
            model: [
                { icon: "arrow-down", value: SystemMonitorService.netRxBps },
                { icon: "arrow-up", value: SystemMonitorService.netTxBps }
            ]
            delegate: Row {
                required property var modelData
                spacing: 2
                AetherIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 11; height: 11
                    name: modelData.icon
                    color: Colors.textMuted
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    // Fixed width so the bar doesn't jitter as digits change.
                    width: 58
                    text: SystemMonitorService.formatRate(modelData.value)
                    color: Colors.textSecondary
                    font.family: Typography.familyMono
                    font.pixelSize: Typography.sizeXs + 1
                }
            }
        }
    }
}
