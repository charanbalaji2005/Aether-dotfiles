import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../components"

// Settings → Accessibility.
ColumnLayout {
    spacing: Metrics.spaceLg

    SettingRow {
        label: "Interface size"
        description: Math.round(Config.accessibility.uiScale * 100) + "% — text, spacing and icons in the shell"
        Slider { implicitWidth: 180; from: 0.85; to: 1.5; value: Config.accessibility.uiScale; format: function(v) { return Math.round(v * 100) + "%"; }; onMoved: function(v) { Config.accessibility.uiScale = Math.round(v * 20) / 20; } }
    }
    SettingRow {
        label: "High contrast"
        description: "Solid surfaces, stronger borders and maximum-contrast text"
        Switch { checked: Config.accessibility.highContrast; onToggled: function(v) { Config.accessibility.highContrast = v; } }
    }
    SettingRow {
        label: "Colour-blind friendly status colours"
        description: "Blue / orange / vermilion (Okabe–Ito) instead of green / amber / red"
        Switch { checked: Config.accessibility.colorBlind; onToggled: function(v) { Config.accessibility.colorBlind = v; } }
    }
    SettingRow {
        label: "Keyboard focus rings"
        Switch { checked: Config.accessibility.focusRings; onToggled: function(v) { Config.accessibility.focusRings = v; } }
    }
    SettingRow {
        label: "Reduce motion"
        Switch { checked: Config.general.reducedMotion; onToggled: function(v) { Config.general.reducedMotion = v; } }
    }
    SettingRow {
        label: "24-hour clock"
        Switch { checked: Config.general.use24Hour; onToggled: function(v) { Config.general.use24Hour = v; } }
    }
    Row {
        spacing: Metrics.spaceSm
        Repeater {
            model: [{ c: Colors.success, l: "OK" }, { c: Colors.warning, l: "Warning" }, { c: Colors.danger, l: "Error" }, { c: Colors.info, l: "Info" }]
            delegate: Rectangle {
                required property var modelData
                width: 90; height: 30; radius: 15; color: modelData.c
                Text { anchors.centerIn: parent; text: modelData.l; color: "#0A0C12"; font.family: Typography.family; font.pixelSize: Typography.sizeXs; font.weight: Typography.weightBold }
            }
        }
    }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "Panels can be driven from the keyboard: Tab moves between controls, Space/Enter activates, arrows adjust sliders and choices, Esc closes. Controls carry accessible names and roles for screen readers where Qt exposes them on Wayland."
        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
    }
}
