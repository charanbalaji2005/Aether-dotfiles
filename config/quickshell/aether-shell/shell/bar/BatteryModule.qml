import QtQuick
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// Battery (laptops only — hidden when UPower reports no laptop battery).
// Style, thresholds and colours come from Settings → Battery; the level
// (normal / low / critical / charging / full) is PowerService's, so the
// icon, the alerts and the lock screen always agree. Hover shows the time
// remaining when UPower provides it. Click opens the control centre.
Capsule {
    id: root
    visible: PowerService.available && Config.bar.showBattery
    implicitWidth: row.implicitWidth + Metrics.spaceMd * 2
    onClicked: EventBus.controlCenterRequested()

    readonly property real pct: PowerService.percentage
    readonly property string style: Config.battery.style || "classic"
    function pick(custom, fallback) { return custom && custom.length === 7 ? custom : fallback; }

    Accessible.role: Accessible.Indicator
    Accessible.name: "Battery " + Math.round(pct) + " percent" + (PowerService.charging ? ", charging" : "")

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Metrics.spaceXs

        BatteryIcon {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            style: root.style
            level: root.pct / 100
            charging: PowerService.charging
            saver: PowerProfileService.batterySaver
            state: PowerService.level
            colorNormal: root.pick(Config.battery.colorNormal, Colors.textPrimary)
            colorLow: root.pick(Config.battery.colorLow, Colors.warning)
            colorCritical: root.pick(Config.battery.colorCritical, Colors.danger)
            colorCharging: root.pick(Config.battery.colorCharging, Colors.success)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: Config.battery.showPercentage && root.style !== "percent"
            text: root.hovered && PowerService.formattedTimeRemaining().length > 0
                ? PowerService.formattedTimeRemaining()
                : Math.round(root.pct) + "%"
            color: PowerService.level === "low" || PowerService.level === "critical" ? icon.tone : Colors.textSecondary
            font.family: Typography.family
            font.pixelSize: Typography.sizeSm
            font.features: { "tnum": 1 }
        }
    }
}
