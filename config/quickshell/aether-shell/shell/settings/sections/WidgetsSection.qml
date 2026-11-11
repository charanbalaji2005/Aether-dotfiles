import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → Widgets.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg
    Component.onCompleted: WidgetService.refresh()
    SettingRow {
        label: "Show desktop widgets"
        description: (Config.widgets.placed || []).length + " placed. SUPER+SHIFT+Y arranges them."
        Switch { checked: Config.widgets.enabled; onToggled: function(v) { Config.widgets.enabled = v; } }
    }
    ChipGroup { options: [{ value: "edit", label: "Arrange widgets on the desktop" }]; current: ""; onSelected: EventBus.widgetEditRequested() }
    SettingRow {
        label: "Snap grid"; description: Config.widgets.grid + " px"
        Slider { implicitWidth: 180; from: 4; to: 64; value: Config.widgets.grid; format: function(v) { return Math.round(v) + " px"; }; onMoved: function(v) { Config.widgets.grid = Math.round(v / 4) * 4; } }
    }
    property bool armThirdParty: false
    SettingRow {
        label: "Allow third-party widgets"
        description: Config.widgets.allowThirdParty
            ? "On. Only widgets you trusted (aether widget trust), at the exact version you trusted, are loaded."
            : "Off (recommended). Only the built-in widgets load."
        RowLayout {
            Text {
                visible: root.armThirdParty
                text: "They run inside the desktop shell — not sandboxed. Click again to allow."
                color: Colors.warning; font.family: Typography.family; font.pixelSize: Typography.sizeXs
            }
            Switch {
                checked: Config.widgets.allowThirdParty
                onToggled: function(v) {
                    if (!v) { Config.widgets.allowThirdParty = false; root.armThirdParty = false; return; }
                    if (!root.armThirdParty) { root.armThirdParty = true; return; }
                    Config.widgets.allowThirdParty = true; root.armThirdParty = false;
                    WidgetService.refresh();
                }
            }
        }
    }
    SectionLabel { text: "Installed"; Layout.topMargin: Metrics.spaceSm }
    Repeater {
        model: WidgetService.catalog
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            Rectangle { width: 8; height: 8; radius: 4; color: modelData.loadable ? Colors.success : modelData.valid ? Colors.warning : Colors.danger }
            Column {
                Layout.fillWidth: true
                Text { text: modelData.name + "  ·  " + modelData.version + (modelData.source === "builtin" ? "  ·  built-in" : ""); color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
                Text { width: parent.width; wrapMode: Text.WordWrap
                       text: !modelData.valid ? "Blocked: " + modelData.problems.slice(0, 3).join("; ")
                           : ("Can see: " + (modelData.permissions.length ? modelData.permissions.join(", ") : "nothing")
                              + (modelData.missingRequirements.length ? " · needs " + modelData.missingRequirements.join(", ") : "")
                              + (modelData.loadable ? "" : " · not loaded: " + modelData.blockedReason))
                       color: modelData.valid ? Colors.textMuted : Colors.danger; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
            }
        }
    }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "Third-party widgets: aether widget install <folder or .zip>, read its files, then aether widget trust <id>. Trust is pinned to the exact files; a changed widget stops loading until trusted again. Checks are static, not a sandbox. Recovery: aether widget disable-third-party. Guide: docs/WIDGETS.md."
        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
    }
}
