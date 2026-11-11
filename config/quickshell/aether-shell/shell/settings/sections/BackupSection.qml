import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → Backup & recovery.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg
    property string armed: ""
    Component.onCompleted: SystemService.loadSnapshots()

    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "Snapshots hold your AetherOS settings, generated Hyprland and terminal files, layouts, profiles and themes — checksummed, and restoring one first snapshots the current state. One is taken automatically before every update, profile, import and reset."
        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm
    }
    RowLayout {
        ChipGroup { options: [{ value: "c", label: "Create snapshot" }]; current: "c"; onSelected: SystemService.createSnapshot() }
        ChipGroup { options: [{ value: "g", label: "Mark current as known-good" }]; current: ""; onSelected: SystemService.markGood() }
    }
    Repeater {
        model: SystemService.snapshots
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: modelData.name + (modelData.lastKnownGood ? "   ★ known-good" : "") + (modelData.valid ? "" : "   (damaged)"); color: modelData.valid ? Colors.textPrimary : Colors.danger; font.family: Typography.family; font.pixelSize: Typography.sizeSm; elide: Text.ElideRight }
            ChipGroup {
                visible: modelData.valid
                options: [{ value: "r", label: root.armed === modelData.name ? "Click to restore" : "Restore" }]
                current: root.armed === modelData.name ? "r" : ""
                onSelected: { if (root.armed === modelData.name) { SystemService.restoreSnapshot(modelData.name); root.armed = ""; } else root.armed = modelData.name; }
            }
        }
    }
    SectionLabel { text: "Reset a section to its defaults"; Layout.topMargin: Metrics.spaceSm }
    ChipGroup {
        Layout.fillWidth: true
        options: ["appearance", "bar", "dock", "island", "effects", "wallpaper", "notifications", "lock", "gestures", "input", "terminal", "accessibility"].map(function(s) { return { value: s, label: s }; })
        current: ""
        onSelected: function(v) { CliService.run("reset-" + v, ["reset-section", v, "--json"], function() {}); }
    }
    SectionLabel { text: "If something breaks"; Layout.topMargin: Metrics.spaceSm }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "aether recover — safe mode, repair fragments, offer the known-good settings.\nHyprland won't start: from a TTY run  Hyprland -c ~/.config/hypr/recovery.conf\nUndo AetherOS entirely:  ./install.sh --rollback      (RECOVERY.md has everything)"
        color: Colors.textSecondary; font.family: Typography.familyMono; font.pixelSize: Typography.sizeXs
    }
}
