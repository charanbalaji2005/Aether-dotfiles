import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → Terminal. Colours follow the shell palette for kitty, foot,
// alacritty and ghostty (`aether theme apply`, run automatically); kitty
// also takes the font/opacity/padding/cursor below and reloads live.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg
    property var terminals: []
    Component.onCompleted: CliService.run("terminals", ["theme", "terminals", "--json"], function(ok, d) { if (ok) root.terminals = d; })

    // Re-generate terminal files when these settings change.
    readonly property string key: JSON.stringify([Config.terminal.opacity, Config.terminal.fontSize, Config.terminal.fontFamily, Config.terminal.padding,
                                                  Config.terminal.cursorShape, Config.terminal.zshProfile, Config.terminal.customProfile])
    property bool _ready: false
    onKeyChanged: if (_ready) apply.restart()
    Timer { id: apply; interval: 600; onTriggered: CliService.run("theme-apply", ["theme", "apply", "--json"], function() {}) }
    Timer { interval: 100; running: true; onTriggered: root._ready = true }

    SettingRow {
        label: "Default terminal"
        description: "Used by SUPER+Return and apps that need a terminal (aether-terminal)"
        ChipGroup {
            Layout.maximumWidth: 380
            options: [{ value: "auto", label: "Automatic" }].concat(root.terminals.filter(function(t) { return t.installed; }).map(function(t) { return { value: t.name, label: t.name }; }))
            current: Config.terminal.preferred
            onSelected: function(v) { Config.terminal.preferred = v; }
        }
    }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: root.terminals.length ? "Installed: " + root.terminals.filter(function(t) { return t.installed; }).map(function(t) { return t.name + (t.themed ? " (themed)" : ""); }).join(", ") : ""
        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
    }

    SectionLabel { text: "Kitty"; Layout.topMargin: Metrics.spaceSm }
    SettingRow {
        label: "Background opacity"
        Slider { implicitWidth: 180; from: 0.3; to: 1; value: Config.terminal.opacity; onMoved: function(v) { Config.terminal.opacity = Math.round(v * 100) / 100; } }
    }
    SettingRow {
        label: "Font size"
        description: Config.terminal.fontSize.toFixed(1) + " pt"
        Slider { implicitWidth: 180; from: 8; to: 20; value: Config.terminal.fontSize; format: function(v) { return v.toFixed(1) + " pt"; }; onMoved: function(v) { Config.terminal.fontSize = Math.round(v * 2) / 2; } }
    }
    SettingRow {
        label: "Font"
        ChipGroup {
            options: ["JetBrains Mono", "Fira Code", "Cascadia Code", "Source Code Pro", "Noto Sans Mono"].map(function(f) { return { value: f, label: f }; })
            current: Config.terminal.fontFamily
            onSelected: function(v) { Config.terminal.fontFamily = v; }
        }
    }
    SettingRow {
        label: "Padding"
        Slider { implicitWidth: 180; from: 0; to: 32; value: Config.terminal.padding; format: function(v) { return Math.round(v) + " px"; }; onMoved: function(v) { Config.terminal.padding = Math.round(v); } }
    }
    SettingRow {
        label: "Cursor"
        SegmentedControl {
            options: [{ value: "beam", label: "Beam" }, { value: "block", label: "Block" }, { value: "underline", label: "Underline" }]
            current: Config.terminal.cursorShape
            onSelected: function(v) { Config.terminal.cursorShape = v; }
        }
    }

    SectionLabel { text: "Zsh profile"; Layout.topMargin: Metrics.spaceSm }
    ChipGroup {
        options: [{ value: "minimal", label: "Minimal" }, { value: "developer", label: "Developer" }, { value: "power", label: "Power user" }, { value: "custom", label: "Custom file" }]
        current: Config.terminal.zshProfile
        onSelected: function(v) { Config.terminal.zshProfile = v; }
    }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: ({ minimal: "History, completion, a two-line git-aware prompt and the base aliases.",
                 developer: "Adds fzf history/file search, zoxide, and git helpers (each only if installed).",
                 power: "Developer plus Starship prompt, larger history and a system summary on new terminals.",
                 custom: "Sources a zsh file of your own — for example your Meridian Shell configuration." })[Config.terminal.zshProfile]
        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
    }
    Rectangle {
        visible: Config.terminal.zshProfile === "custom"
        Layout.fillWidth: true; implicitHeight: 32; radius: 16
        color: Colors.withAlpha(Colors.surface, 0.9); border.width: 1; border.color: pathIn.activeFocus ? Colors.accent : Colors.border
        TextInput {
            id: pathIn
            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
            verticalAlignment: TextInput.AlignVCenter
            text: Config.terminal.customProfile
            color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm
            onEditingFinished: if (text.trim().length === 0 || text.trim().charAt(0) === "/") Config.terminal.customProfile = text.trim()
        }
        Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; visible: pathIn.text.length === 0; text: "absolute path, e.g. ~/.config/meridian/init.zsh expanded"; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
    }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "Zsh is your login shell only if you chose it: AetherOS never runs chsh. To switch: chsh -s /usr/bin/zsh"
        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
    }
}
