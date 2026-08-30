import QtQuick
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

Capsule {
    id: root
    interactive: false
    visible: PowerService.available && Config.bar.showBattery
    implicitWidth: row.implicitWidth + Metrics.spaceMd * 2

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Metrics.spaceXs

        AetherIcon {
            width: 18
            height: 12
            anchors.verticalCenter: parent.verticalCenter
            name: PowerService.charging ? "battery-charging" : "battery"
            batteryLevel: PowerService.percentage / 100
            color: (PowerService.percentage <= 15 && !PowerService.charging) ? Colors.danger : Colors.textPrimary
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(PowerService.percentage) + "%"
            color: Colors.textSecondary
            font.family: Typography.family
            font.pixelSize: Typography.sizeSm
        }
    }
}
