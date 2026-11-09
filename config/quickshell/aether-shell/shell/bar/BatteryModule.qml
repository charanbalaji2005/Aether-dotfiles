import QtQuick
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// Battery level (laptops only — hidden when UPower reports no laptop
// battery). Warning colour at 20 %, danger at 10 %; hover shows the time
// remaining when UPower provides it. Click opens the control centre.
Capsule {
    id: root
    visible: PowerService.available && Config.bar.showBattery
    implicitWidth: row.implicitWidth + Metrics.spaceMd * 2
    onClicked: EventBus.controlCenterRequested()

    readonly property real pct: PowerService.percentage
    readonly property color levelColor: PowerService.charging ? Colors.success
        : pct <= 10 ? Colors.danger
        : pct <= 20 ? Colors.warning
        : Colors.textPrimary

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Metrics.spaceXs

        AetherIcon {
            width: 18
            height: 12
            anchors.verticalCenter: parent.verticalCenter
            name: PowerService.charging ? "battery-charging" : "battery"
            batteryLevel: root.pct / 100
            color: root.levelColor
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.hovered && PowerService.formattedTimeRemaining().length > 0
                ? PowerService.formattedTimeRemaining()
                : Math.round(root.pct) + "%"
            color: root.pct <= 20 && !PowerService.charging ? root.levelColor : Colors.textSecondary
            font.family: Typography.family
            font.pixelSize: Typography.sizeSm
        }
    }
}
