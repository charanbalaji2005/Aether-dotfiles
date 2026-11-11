import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → Mouse & touchpad (applied live through Hyprland, saved to input.conf).
ColumnLayout {
    spacing: Metrics.spaceLg
    SectionLabel { text: "Pointer" }
    SettingRow {
        label: "Speed"; description: (Config.input.sensitivity >= 0 ? "+" : "") + Config.input.sensitivity.toFixed(2)
        Slider { implicitWidth: 180; from: -1; to: 1; value: Config.input.sensitivity; format: function(v) { return v.toFixed(2); }; onMoved: function(v) { Config.input.sensitivity = Math.round(v * 20) / 20; } }
    }
    SettingRow {
        label: "Acceleration"; description: "Flat moves the pointer exactly as far as you move the mouse (preferred for games)"
        SegmentedControl { options: [{ value: "adaptive", label: "Adaptive" }, { value: "flat", label: "Flat" }]; current: Config.input.accelProfile; onSelected: function(v) { Config.input.accelProfile = v; } }
    }
    SettingRow { label: "Natural scrolling (mouse)"; Switch { checked: Config.input.naturalScroll; onToggled: function(v) { Config.input.naturalScroll = v; } } }
    SettingRow {
        label: "Scroll speed"; description: Config.input.scrollFactor.toFixed(1) + "×"
        Slider { implicitWidth: 180; from: 0.2; to: 3; value: Config.input.scrollFactor; format: function(v) { return v.toFixed(1) + "×"; }; onMoved: function(v) { Config.input.scrollFactor = Math.round(v * 10) / 10; } }
    }
    SectionLabel { text: "Touchpad"; Layout.topMargin: Metrics.spaceSm }
    SettingRow { label: "Natural scrolling"; Switch { checked: Config.input.touchpadNaturalScroll; onToggled: function(v) { Config.input.touchpadNaturalScroll = v; } } }
    SettingRow { label: "Tap to click"; Switch { checked: Config.input.tapToClick; onToggled: function(v) { Config.input.tapToClick = v; } } }
    SettingRow { label: "Disable while typing"; Switch { checked: Config.input.disableWhileTyping; onToggled: function(v) { Config.input.disableWhileTyping = v; } } }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: SystemSettingsService.inputError.length ? "Not applied: " + SystemSettingsService.inputError : "Gestures are in Settings → Gestures."
        color: SystemSettingsService.inputError.length ? Colors.danger : Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
    }
}
