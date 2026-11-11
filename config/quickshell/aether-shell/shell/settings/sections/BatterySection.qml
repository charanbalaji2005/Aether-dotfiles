import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → Battery: icon family with live previews, thresholds, colours,
// alerts. Every value shown comes from UPower; nothing is simulated.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg

    readonly property real pct: PowerService.available ? PowerService.percentage : 72
    function pick(custom, fallback) { return custom && custom.length === 7 ? custom : fallback; }

    Text {
        visible: !PowerService.available
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "No laptop battery reported by UPower — previews use a sample level, and nothing is shown in the bar."
        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm
    }

    SectionLabel { text: "Icon style" }
    Flow {
        Layout.fillWidth: true
        spacing: Metrics.spaceSm
        Repeater {
            model: [
                { id: "classic", label: "Classic" }, { id: "outline", label: "Outline" }, { id: "filled", label: "Filled" },
                { id: "segmented", label: "Segmented" }, { id: "circular", label: "Circular" }, { id: "compact", label: "Compact" },
                { id: "bar", label: "Bar" }, { id: "percent", label: "Number" }
            ]
            delegate: MotionCard {
                required property var modelData
                required property int index
                width: 104; height: 92
                index: index
                selected: Config.battery.style === modelData.id
                onClicked: Config.battery.style = modelData.id
                Column {
                    anchors.centerIn: parent
                    spacing: Metrics.spaceSm
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10
                        BatteryIcon { style: modelData.id; level: root.pct / 100; state: "normal"; colorNormal: root.pick(Config.battery.colorNormal, Colors.textPrimary) }
                        BatteryIcon { style: modelData.id; level: 0.6; charging: true; colorCharging: root.pick(Config.battery.colorCharging, Colors.success) }
                        BatteryIcon { style: modelData.id; level: 0.08; state: "critical"; colorCritical: root.pick(Config.battery.colorCritical, Colors.danger) }
                    }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
                }
            }
        }
    }
    SettingRow {
        label: "Show percentage next to the icon"
        Switch { checked: Config.battery.showPercentage; onToggled: function(v) { Config.battery.showPercentage = v; } }
    }

    SectionLabel { text: "Levels and alerts"; Layout.topMargin: Metrics.spaceSm }
    SettingRow {
        label: "Low battery at"
        description: Config.battery.lowThreshold + "%"
        Slider { implicitWidth: 180; from: 5; to: 50; value: Config.battery.lowThreshold; format: function(v) { return Math.round(v) + "%"; }
                 onMoved: function(v) { Config.battery.lowThreshold = Math.max(Math.round(v), Config.battery.criticalThreshold + 1); } }
    }
    SettingRow {
        label: "Critical at"
        description: Config.battery.criticalThreshold + "% — always notifies"
        Slider { implicitWidth: 180; from: 2; to: 25; value: Config.battery.criticalThreshold; format: function(v) { return Math.round(v) + "%"; }
                 onMoved: function(v) { Config.battery.criticalThreshold = Math.min(Math.round(v), Config.battery.lowThreshold - 1); } }
    }
    SettingRow { label: "Notify when low"; Switch { checked: Config.battery.notifyLow; onToggled: function(v) { Config.battery.notifyLow = v; } } }
    SettingRow { label: "Notify when fully charged"; Switch { checked: Config.battery.notifyFull; onToggled: function(v) { Config.battery.notifyFull = v; } } }

    SectionLabel { text: "Colours"; Layout.topMargin: Metrics.spaceSm }
    Repeater {
        model: [{ key: "colorNormal", label: "Normal", fallback: "textPrimary" }, { key: "colorCharging", label: "Charging", fallback: "success" },
                { key: "colorLow", label: "Low", fallback: "warning" }, { key: "colorCritical", label: "Critical", fallback: "danger" }]
        delegate: SettingRow {
            id: colorRow
            required property var modelData
            label: modelData.label
            description: Config.battery[modelData.key] ? Config.battery[modelData.key] : "Theme colour"
            Row {
                spacing: 6
                Repeater {
                    model: ["", "#4ADE80", "#38BDF8", "#FBBF24", "#FB923C", "#F87171", "#B48CFF", "#EDEFF7"]
                    delegate: ColorSwatch {
                        required property string modelData
                        swatchColor: modelData === "" ? Colors[colorRow.modelData.fallback] : modelData
                        selected: (Config.battery[colorRow.modelData.key] || "") === modelData
                        onClicked: Config.battery[colorRow.modelData.key] = modelData
                    }
                }
            }
        }
    }
    InfoText {
        visible: PowerService.available
        text: "Now: " + Math.round(PowerService.percentage) + "% · " + PowerService.level
              + (PowerService.formattedTimeRemaining() ? " · " + PowerService.formattedTimeRemaining() + (PowerService.charging ? " to full" : " left") : "")
              + (PowerService.health >= 0 ? " · health " + Math.round(PowerService.health) + "%" : "")
              + (PowerProfileService.batterySaver ? " · power saver on" : "")
    }
    component InfoText: Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
}
