import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → Widgets.
ColumnLayout {
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
    SectionLabel { text: "Installed"; Layout.topMargin: Metrics.spaceSm }
    Repeater {
        model: WidgetService.catalog
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            Rectangle { width: 8; height: 8; radius: 4; color: modelData.valid ? Colors.success : Colors.danger }
            Column {
                Layout.fillWidth: true
                Text { text: modelData.name + "  ·  " + modelData.version + (modelData.source === "builtin" ? "  ·  built-in" : ""); color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
                Text { width: parent.width; wrapMode: Text.WordWrap
                       text: modelData.valid ? ("Can see: " + (modelData.permissions.length ? modelData.permissions.join(", ") : "nothing") + (modelData.missingRequirements.length ? " · needs " + modelData.missingRequirements.join(", ") : ""))
                                             : "Blocked: " + modelData.problems.slice(0, 3).join("; ")
                       color: modelData.valid ? Colors.textMuted : Colors.danger; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
            }
        }
    }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "Install a widget: aether widget install <folder or .zip>. Each widget is checked before installing and again when loaded: it may only use Qt Quick and the data its manifest declares. This is a static check, not a sandbox — install widgets from authors you trust. Guide: docs/WIDGETS.md."
        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
    }
}
