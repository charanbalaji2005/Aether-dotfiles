import QtQuick
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// CPU · RAM · GPU usage (with temperatures where the hardware exposes them).
// A metric that can't be read is omitted from the bar, not shown as 0 —
// the dashboard explains why it is unavailable. Click opens the dashboard.
Capsule {
    id: root
    visible: Config.bar.showStats
    implicitWidth: row.implicitWidth + Metrics.spaceMd * 2
    onClicked: EventBus.dashboardRequested()

    readonly property var gpu: SystemMonitorService.primaryGpu
    readonly property bool gpuUsable: gpu !== null && gpu.state === "active" && (gpu.usage !== null || gpu.tempC !== null)

    component Stat: Row {
        id: stat
        property string icon: ""
        property real ratio: -1
        property real temp: -1
        spacing: 3
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined

        AetherIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: Metrics.iconSm; height: Metrics.iconSm
            name: stat.icon
            color: stat.ratio >= 0 ? Colors.load(stat.ratio) : Colors.textSecondary
        }
        Text {
            visible: stat.ratio >= 0
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(stat.ratio * 100) + "%"
            color: Colors.textSecondary
            font.family: Typography.familyMono
            font.pixelSize: Typography.sizeXs + 1
        }
        Text {
            visible: Config.bar.showTemperatures && stat.temp >= 0
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(stat.temp) + "°"
            color: Colors.temperature(stat.temp)
            font.family: Typography.familyMono
            font.pixelSize: Typography.sizeXs + 1
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Metrics.spaceMd

        Stat {
            icon: "cpu"
            ratio: SystemMonitorService.cpuUsage
            temp: SystemMonitorService.cpuTemp
        }
        Stat {
            icon: "memory"
            ratio: SystemMonitorService.memUsage
        }
        Stat {
            visible: root.gpuUsable
            icon: "gpu"
            ratio: root.gpuUsable && root.gpu.usage !== null ? root.gpu.usage : -1
            temp: root.gpuUsable && root.gpu.tempC !== null ? root.gpu.tempC : -1
        }
    }
}
