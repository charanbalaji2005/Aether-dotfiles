import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → Dock & island.
ColumnLayout {
    spacing: Metrics.spaceLg

    SectionLabel { text: "Dock" }
    SettingRow {
        label: "Show the dock"
        description: "Favourites from the launcher plus running apps. SUPER+Z toggles it"
        Switch { checked: Config.dock.enabled; onToggled: function(v) { Config.dock.enabled = v; } }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Metrics.spaceLg
        enabled: Config.dock.enabled
        opacity: enabled ? 1 : 0.5
        SettingRow {
            label: "Position"
            SegmentedControl {
                options: [{ value: "bottom", label: "Bottom" }, { value: "left", label: "Left" }, { value: "right", label: "Right" }]
                current: Config.dock.position
                onSelected: function(v) { Config.dock.position = v; }
            }
        }
        SettingRow {
            label: "Icon size"
            description: Config.dock.iconSize + " px"
            Slider { implicitWidth: 180; from: 28; to: 72; value: Config.dock.iconSize; format: function(v) { return Math.round(v) + " px"; }; onMoved: function(v) { Config.dock.iconSize = Math.round(v); } }
        }
        SettingRow {
            label: "Magnification"
            description: Config.dock.magnification <= 1.01 ? "Off" : Math.round((Config.dock.magnification - 1) * 100) + "% larger under the pointer"
            Slider { implicitWidth: 180; from: 1.0; to: 2.0; value: Config.dock.magnification; format: function(v) { return v <= 1.01 ? "off" : "+" + Math.round((v - 1) * 100) + "%"; }; onMoved: function(v) { Config.dock.magnification = Math.round(v * 20) / 20; } }
        }
        SettingRow {
            label: "Background opacity"
            Slider { implicitWidth: 180; from: 0; to: 1; value: Config.dock.opacity; onMoved: function(v) { Config.dock.opacity = Math.round(v * 100) / 100; } }
        }
        SettingRow {
            label: "Hide automatically"
            description: "Reveals when the pointer touches the screen edge, or on an empty workspace"
            Switch { checked: Config.dock.autoHide; onToggled: function(v) { Config.dock.autoHide = v; } }
        }
        SettingRow {
            label: "Show running apps"
            Switch { checked: Config.dock.showRunning; onToggled: function(v) { Config.dock.showRunning = v; } }
        }
        SettingRow { label: "Show recent apps"; Switch { checked: Config.dock.showRecent; onToggled: function(v) { Config.dock.showRecent = v; } } }
        SettingRow { label: "Window previews in the menu"; description: "Live thumbnails where Quickshell supports screen capture"; Switch { checked: Config.dock.previews; onToggled: function(v) { Config.dock.previews = v; } } }
        SettingRow {
            label: "Show Trash"
            Switch { checked: Config.dock.showTrash; onToggled: function(v) { Config.dock.showTrash = v; } }
        }
    }

    SectionLabel { text: "Dynamic Island"; Layout.topMargin: Metrics.spaceSm }
    SettingRow {
        label: "Show the island"
        description: "Appears only while something is happening; hover or click to expand, right-click to switch activity"
        Switch { checked: Config.island.enabled; onToggled: function(v) { Config.island.enabled = v; } }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Metrics.spaceLg
        enabled: Config.island.enabled
        opacity: enabled ? 1 : 0.5
        SettingRow { label: "Media"; Switch { checked: Config.island.showMedia; onToggled: function(v) { Config.island.showMedia = v; } } }
        SettingRow {
            label: "Audio visualiser"
            description: VisualizerService.available ? "Spectrum of what you hear (system output only — never the microphone)" : "Needs cava (sudo dnf install cava)"
            Switch { checked: Config.island.visualizer; enabled: VisualizerService.available; onToggled: function(v) { Config.island.visualizer = v; } }
        }
        SettingRow { label: "Timers and focus sessions"; Switch { checked: Config.island.showTimers; onToggled: function(v) { Config.island.showTimers = v; } } }
        SettingRow { label: "Screen recording"; Switch { checked: Config.island.showRecording; onToggled: function(v) { Config.island.showRecording = v; } } }
        SettingRow { label: "Charging and battery alerts"; Switch { checked: Config.island.showBattery; onToggled: function(v) { Config.island.showBattery = v; } } }
        SettingRow { label: "Important notifications"; Switch { checked: Config.island.showNotifications; onToggled: function(v) { Config.island.showNotifications = v; } } }
    }

    SectionLabel { text: "Timers"; Layout.topMargin: Metrics.spaceSm }
    RowLayout {
        spacing: Metrics.spaceSm
        Repeater {
            model: [{ m: 1, l: "1 min" }, { m: 5, l: "5 min" }, { m: 10, l: "10 min" }, { m: 25, l: "25 min" }]
            delegate: ChipGroup {
                required property var modelData
                options: [{ value: String(modelData.m), label: modelData.l }]
                current: ""
                onSelected: function(v) { TimerService.startCountdown(parseInt(v) * 60); }
            }
        }
        ChipGroup { options: [{ value: "focus", label: TimerService.focusActive ? "Stop focus" : "Focus session" }]; current: TimerService.focusActive ? "focus" : ""; onSelected: function(v) { if (TimerService.focusActive) TimerService.stopFocus(); else TimerService.startFocus(25); } }
        ChipGroup { options: [{ value: "sw", label: TimerService.stopwatchRunning ? "Pause stopwatch" : "Stopwatch" }]; current: TimerService.stopwatchRunning ? "sw" : ""; onSelected: function(v) { if (TimerService.stopwatchRunning) TimerService.pauseStopwatch(); else TimerService.startStopwatch(); } }
    }
    SettingRow {
        label: "Do Not Disturb during focus sessions"
        Switch { checked: TimerService.focusDnd; onToggled: function(v) { TimerService.focusDnd = v; } }
    }

    SectionLabel { text: "Island activity"; Layout.topMargin: Metrics.spaceSm }
    SettingRow { label: "Microphone and camera in use"; Switch { checked: Config.island.showPrivacy; onToggled: function(v) { Config.island.showPrivacy = v; } } }
    SettingRow { label: "Network and VPN changes"; Switch { checked: Config.island.showNetwork; onToggled: function(v) { Config.island.showNetwork = v; } } }
    SettingRow { label: "Screenshots"; Switch { checked: Config.island.showScreenshots; onToggled: function(v) { Config.island.showScreenshots = v; } } }
    SettingRow { label: "Clipboard copies"; description: "Shows “Copied” — never the content"; Switch { checked: Config.island.showClipboard; onToggled: function(v) { Config.island.showClipboard = v; } } }
    SettingRow { label: "Messages from your scripts"; description: "aether island post \"Build finished\" (max 6 a minute)"; Switch { checked: Config.island.allowExternal; onToggled: function(v) { Config.island.allowExternal = v; } } }
    SettingRow {
        label: "Show events for"; description: Config.island.eventSeconds + " s"
        Slider { implicitWidth: 180; from: 2; to: 15; value: Config.island.eventSeconds; format: function(v) { return Math.round(v) + " s"; }; onMoved: function(v) { Config.island.eventSeconds = Math.round(v); } }
    }
    SectionLabel { text: "Recent island activity"; Layout.topMargin: Metrics.spaceSm }
    Repeater {
        model: IslandService.history.slice(0, 10)
        delegate: Text { required property var modelData; Layout.fillWidth: true; elide: Text.ElideRight
                         text: modelData.time + "  " + modelData.kind + "  " + (modelData.payload.text || "") + (modelData.payload.body ? " — " + modelData.payload.body : "")
                         color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
    }
    Text { visible: IslandService.history.length === 0; text: "Nothing yet this session."; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
}
