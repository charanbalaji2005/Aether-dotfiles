import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → Startup applications (standard XDG autostart).
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg
    property var entries: []
    property string message: ""
    property string addFilter: ""
    function reload() { CliService.run("autostart", ["autostart", "list", "--json"], function(ok, d) { if (ok) root.entries = d; }); }
    function act(cmd, id) { CliService.run("autostart-" + cmd, ["autostart", cmd, id, "--json"], function(ok, d, e) { root.message = ok ? "" : (d && d.problems ? d.problems.join("; ") : (d && d.error) || e); root.reload(); }); }
    Component.onCompleted: reload()

    SettingRow {
        label: "Start these apps when I log in"
        description: "Runs autostart entries through systemd at login (aether autostart run)"
        Switch { checked: Config.general.xdgAutostart; onToggled: function(v) { Config.general.xdgAutostart = v; } }
    }
    Repeater {
        model: root.entries
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            opacity: modelData.appliesHere ? 1 : 0.5
            Column {
                Layout.fillWidth: true
                Text { text: modelData.name; color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
                Text { text: modelData.id + (modelData.appliesHere ? "" : " — only for other desktops"); color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
            }
            IconButton { visible: modelData.source === "user"; icon: "trash"; onClicked: root.act("remove", modelData.id) }
            Switch { checked: modelData.enabled; onToggled: function(v) { root.act(v ? "enable" : "disable", modelData.id); } }
        }
    }
    SectionLabel { text: "Add an app"; Layout.topMargin: Metrics.spaceSm }
    Rectangle {
        Layout.fillWidth: true; implicitHeight: 32; radius: 16
        color: Colors.withAlpha(Colors.surface, 0.9); border.width: 1; border.color: af.activeFocus ? Colors.accent : Colors.border
        TextInput { id: af; anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; verticalAlignment: TextInput.AlignVCenter
                    color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; onTextChanged: root.addFilter = text }
        Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; visible: af.text.length === 0; text: "Search installed apps"; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
    }
    ChipGroup {
        Layout.fillWidth: true
        visible: root.addFilter.length >= 2
        options: ApplicationService.search(root.addFilter).slice(0, 8).map(function(a) { return { value: a.id, label: a.name }; })
        current: ""
        onSelected: function(v) { root.act("add", v); af.text = ""; }
    }
    Text { visible: root.message.length > 0; text: root.message; color: Colors.danger; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
}
