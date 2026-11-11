import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → Workspaces: names, icons, wallpapers, app rules, session.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg
    property int ws: 1
    property string ruleApp: ""
    property int ruleWs: 1
    property string sessionMessage: ""
    readonly property var iconChoices: ["", "code", "globe", "music", "image", "gear", "activity", "star", "display", "clipboard", "camera", "sparkle"]

    ChipGroup {
        options: [1, 2, 3, 4, 5, 6, 7, 8, 9].map(function(i) { return { value: String(i), label: (Config.workspaces.names || {})[String(i)] ? i + " · " + Config.workspaces.names[String(i)] : String(i) }; })
        current: String(root.ws)
        onSelected: function(v) { root.ws = parseInt(v); nameIn.text = (Config.workspaces.names || {})[v] || ""; }
    }
    SettingRow {
        label: "Name"
        Rectangle {
            implicitWidth: 200; implicitHeight: 30; radius: 15
            color: Colors.withAlpha(Colors.surface, 0.9); border.width: 1; border.color: nameIn.activeFocus ? Colors.accent : Colors.border
            TextInput {
                id: nameIn
                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; verticalAlignment: TextInput.AlignVCenter
                color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm
                text: (Config.workspaces.names || {})[String(root.ws)] || ""
                validator: RegularExpressionValidator { regularExpression: /[\w .:@+-]{0,32}/ }
                onEditingFinished: {
                    const m = Object.assign({}, Config.workspaces.names || {});
                    if (text.trim()) m[String(root.ws)] = text.trim(); else delete m[String(root.ws)];
                    Config.workspaces.names = m;
                }
            }
        }
    }
    SettingRow {
        label: "Icon"
        Row {
            spacing: 4
            Repeater {
                model: root.iconChoices
                delegate: Rectangle {
                    required property string modelData
                    width: 30; height: 30; radius: 8
                    readonly property bool on: ((Config.workspaces.icons || {})[String(root.ws)] || "") === modelData
                    color: on ? Colors.accentSoft : "transparent"; border.width: on ? 1 : 0; border.color: Colors.accent
                    AetherIcon { anchors.centerIn: parent; visible: modelData.length > 0; width: 15; height: 15; name: modelData; color: Colors.textSecondary }
                    Text { anchors.centerIn: parent; visible: modelData.length === 0; text: "#"; color: Colors.textSecondary; font.pixelSize: Typography.sizeSm }
                    MouseArea { anchors.fill: parent; onClicked: { const m = Object.assign({}, Config.workspaces.icons || {}); if (modelData) m[String(root.ws)] = modelData; else delete m[String(root.ws)]; Config.workspaces.icons = m; } }
                }
            }
        }
    }
    SettingRow {
        label: "Wallpaper on this workspace"
        description: (Config.wallpaper.perWorkspace || {})[String(root.ws)] ? (Config.wallpaper.perWorkspace[String(root.ws)].split("/").pop()) : "The normal wallpaper"
        RowLayout {
            ChipGroup { options: [{ value: "use", label: "Use current wallpaper" }]; current: ""
                onSelected: { const m = Object.assign({}, Config.wallpaper.perWorkspace || {}); m[String(root.ws)] = WallpaperService.currentWallpaper; Config.wallpaper.perWorkspace = m; } }
            IconButton { icon: "trash"; onClicked: { const m = Object.assign({}, Config.wallpaper.perWorkspace || {}); delete m[String(root.ws)]; Config.wallpaper.perWorkspace = m; } }
        }
    }

    SectionLabel { text: "Open apps on a workspace"; Layout.topMargin: Metrics.spaceSm }
    Repeater {
        model: Config.workspaces.appRules || []
        delegate: RowLayout {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: modelData.app + "  →  workspace " + modelData.workspace + (modelData.silent ? " (in the background)" : ""); color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
            IconButton { icon: "trash"; onClicked: Config.workspaces.appRules = (Config.workspaces.appRules || []).filter(function(_, i) { return i !== index; }) }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        ChipGroup {
            Layout.fillWidth: true
            options: WindowService.runningClasses.slice(0, 10).map(function(c) { return { value: c, label: c }; })
            current: root.ruleApp
            onSelected: function(v) { root.ruleApp = v; }
        }
    }
    RowLayout {
        visible: root.ruleApp.length > 0
        Text { text: root.ruleApp + " →"; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
        ChipGroup { options: [1, 2, 3, 4, 5, 6, 7, 8, 9].map(function(i) { return { value: String(i), label: String(i) }; }); current: String(root.ruleWs); onSelected: function(v) { root.ruleWs = parseInt(v); } }
        ChipGroup { options: [{ value: "add", label: "Add rule" }]; current: "add"
            onSelected: { Config.workspaces.appRules = (Config.workspaces.appRules || []).filter(function(r) { return r.app !== root.ruleApp; }).concat([{ app: root.ruleApp, workspace: root.ruleWs, silent: true }]); root.ruleApp = ""; } }
    }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: SystemSettingsService.rulesError.length ? "Not applied: " + SystemSettingsService.rulesError : "Pick a running app above, then a workspace. Rules use your Hyprland version's syntax."
        color: SystemSettingsService.rulesError.length ? Colors.danger : Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
    }

    SectionLabel { text: "Session"; Layout.topMargin: Metrics.spaceSm }
    SettingRow {
        label: "Reopen saved apps at login"
        description: "Apps are reopened from their installed launchers onto their workspaces; documents and tabs are each app's own business"
        Switch { checked: Config.workspaces.restoreSession; onToggled: function(v) { Config.workspaces.restoreSession = v; } }
    }
    RowLayout {
        ChipGroup { options: [{ value: "save", label: "Save open apps now" }]; current: ""
            onSelected: CliService.run("ws-save", ["workspace", "save", "--json"], function(ok, d, e) { root.sessionMessage = ok ? "Saved " + d.saved + " app(s)." + (d.skipped.length ? " Not recognised: " + d.skipped.join(", ") : "") : e; }) }
        ChipGroup { options: [{ value: "restore", label: "Restore now" }]; current: ""
            onSelected: CliService.run("ws-restore", ["workspace", "restore", "--json"], function(ok, d, e) { root.sessionMessage = ok ? "Opened " + d.launched.length + " app(s)." : ((d && d.error) || e); }) }
    }
    Text { visible: root.sessionMessage.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: root.sessionMessage; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
}
