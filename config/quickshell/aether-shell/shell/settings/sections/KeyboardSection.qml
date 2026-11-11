import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → Keyboard. Layouts come from the system's XKB rules (only real
// layouts can be chosen); changes are applied live and saved to input.conf.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg
    property var catalog: null
    property string filter: ""
    Component.onCompleted: CliService.run("xkb", ["input", "layouts", "--json"], function(ok, d) { if (ok) root.catalog = d; })

    readonly property var layouts: (Config.input.kbLayout || "us").split(",").filter(function(x) { return x.length; })
    function setLayouts(list) {
        Config.input.kbLayout = list.join(",");
        // Keep variants aligned with layouts (empty = default variant).
        const v = (Config.input.kbVariant || "").split(",");
        Config.input.kbVariant = list.map(function(_, i) { return v[i] || ""; }).join(",").replace(/^,+$/, "");
    }

    SectionLabel { text: "Layouts" }
    Flow {
        Layout.fillWidth: true
        spacing: Metrics.spaceXs
        Repeater {
            model: root.layouts
            delegate: Rectangle {
                required property string modelData
                required property int index
                implicitWidth: lt.implicitWidth + 40; implicitHeight: 30; radius: 15
                color: Colors.accentSoft; border.width: 1; border.color: Colors.withAlpha(Colors.accent, 0.4)
                Text { id: lt; anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                       text: (index + 1) + ". " + (root.catalog && root.catalog.layouts[modelData] ? root.catalog.layouts[modelData] : modelData)
                       color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
                AetherIcon {
                    visible: root.layouts.length > 1
                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    width: 10; height: 10; name: "close"; color: Colors.textSecondary
                    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.setLayouts(root.layouts.filter(function(_, i) { return i !== index; })) }
                }
            }
        }
    }
    Rectangle {
        Layout.fillWidth: true; implicitHeight: 32; radius: 16
        color: Colors.withAlpha(Colors.surface, 0.9); border.width: 1; border.color: find.activeFocus ? Colors.accent : Colors.border
        TextInput { id: find; anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; verticalAlignment: TextInput.AlignVCenter
                    color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; onTextChanged: root.filter = text.toLowerCase() }
        Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; visible: find.text.length === 0
               text: root.catalog && !root.catalog.available ? "XKB rules not found — layouts can't be listed" : "Add a layout: type a language or code"
               color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
    }
    ChipGroup {
        Layout.fillWidth: true
        visible: root.filter.length >= 2 && root.catalog
        options: !root.catalog ? [] : Object.keys(root.catalog.layouts).filter(function(k) {
            return root.layouts.indexOf(k) < 0 && (k.indexOf(root.filter) === 0 || root.catalog.layouts[k].toLowerCase().indexOf(root.filter) >= 0);
        }).slice(0, 12).map(function(k) { return { value: k, label: root.catalog.layouts[k] + " (" + k + ")" }; })
        current: ""
        onSelected: function(v) { root.setLayouts(root.layouts.concat([v]).slice(0, 4)); find.text = ""; }
    }
    SettingRow {
        visible: root.layouts.length > 1
        label: "Switch layouts with"
        ChipGroup {
            options: [{ value: "grp:alt_shift_toggle", label: "Alt+Shift" }, { value: "grp:win_space_toggle", label: "Super+Space" }, { value: "grp:ctrl_shift_toggle", label: "Ctrl+Shift" }]
            current: ((Config.input.kbOptions || "").split(",").find(function(o) { return o.indexOf("grp:") === 0; })) || ""
            onSelected: function(v) {
                const rest = (Config.input.kbOptions || "").split(",").filter(function(o) { return o && o.indexOf("grp:") !== 0; });
                Config.input.kbOptions = rest.concat([v]).join(",");
            }
        }
    }
    SettingRow {
        label: "Caps Lock"
        ChipGroup {
            options: [{ value: "", label: "Caps Lock" }, { value: "caps:escape", label: "Escape" }, { value: "ctrl:nocaps", label: "Control" }, { value: "caps:none", label: "Off" }]
            current: ((Config.input.kbOptions || "").split(",").find(function(o) { return o.indexOf("caps:") === 0 || o === "ctrl:nocaps"; })) || ""
            onSelected: function(v) {
                const rest = (Config.input.kbOptions || "").split(",").filter(function(o) { return o && o.indexOf("caps:") !== 0 && o !== "ctrl:nocaps"; });
                Config.input.kbOptions = rest.concat(v ? [v] : []).join(",");
            }
        }
    }
    SectionLabel { text: "Typing"; Layout.topMargin: Metrics.spaceSm }
    SettingRow {
        label: "Repeat delay"; description: Config.input.repeatDelay + " ms before a held key repeats"
        Slider { implicitWidth: 180; from: 150; to: 1000; value: Config.input.repeatDelay; format: function(v) { return Math.round(v) + " ms"; }; onMoved: function(v) { Config.input.repeatDelay = Math.round(v / 10) * 10; } }
    }
    SettingRow {
        label: "Repeat rate"; description: Config.input.repeatRate + " characters per second"
        Slider { implicitWidth: 180; from: 5; to: 100; value: Config.input.repeatRate; format: function(v) { return Math.round(v) + "/s"; }; onMoved: function(v) { Config.input.repeatRate = Math.round(v); } }
    }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        visible: SystemSettingsService.inputError.length > 0
        text: "Not applied: " + SystemSettingsService.inputError
        color: Colors.danger; font.family: Typography.family; font.pixelSize: Typography.sizeXs
    }
}
