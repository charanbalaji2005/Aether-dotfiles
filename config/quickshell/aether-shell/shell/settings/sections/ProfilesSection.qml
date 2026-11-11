import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → Profiles: whole-desktop looks. Applying one snapshots your
// current settings first; "Undo" restores that snapshot.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg
    property string saveName: ""
    Component.onCompleted: ProfileService.refresh()

    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "A profile changes only the settings it lists (bar, glass, effects, dock, wallpaper effects…) and the matching Hyprland visual profile. Your wallpapers, favourites and other files are untouched."
        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm
    }
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        rowSpacing: Metrics.spaceSm; columnSpacing: Metrics.spaceSm
        Repeater {
            model: ProfileService.profiles
            delegate: MotionCard {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: 70
                index: index
                selected: ProfileService.lastApplied === modelData.name
                onClicked: ProfileService.apply(modelData.name)
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: Metrics.spaceMd
                    spacing: 2
                    Text { text: modelData.label + (modelData.builtin ? "" : "  ·  yours"); color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeMd; font.weight: Typography.weightSemibold }
                    Text { Layout.fillWidth: true; text: modelData.error ? "Invalid: " + modelData.error : modelData.summary; color: modelData.error ? Colors.danger : Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: ProfileService.error.length ? ProfileService.error : (ProfileService.lastApplied ? "Applied: " + ProfileService.lastApplied : "")
            color: ProfileService.error.length ? Colors.danger : Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm
        }
        ChipGroup { visible: ProfileService.lastUndo.length > 0; options: [{ value: "u", label: "Undo" }]; current: ""; onSelected: ProfileService.undo() }
    }
    SectionLabel { text: "Save the current look"; Layout.topMargin: Metrics.spaceSm }
    RowLayout {
        Layout.fillWidth: true
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 32; radius: 16
            color: Colors.withAlpha(Colors.surface, 0.9); border.width: 1; border.color: nameIn.activeFocus ? Colors.accent : Colors.border
            TextInput {
                id: nameIn
                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm
                validator: RegularExpressionValidator { regularExpression: /[a-z0-9][a-z0-9-]{0,39}/ }
                onTextChanged: root.saveName = text
            }
            Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; visible: nameIn.text.length === 0; text: "profile name (lowercase, digits, -)"; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
        }
        ChipGroup { options: [{ value: "s", label: "Save" }]; current: root.saveName.length ? "s" : ""; onSelected: if (root.saveName.length) { ProfileService.saveCurrent(root.saveName, root.saveName); nameIn.text = ""; } }
    }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "Share a profile with: aether profile export <name> file.json — import one with: aether profile import file.json <name>. Imports are validated; profiles can't contain commands or automation rules."
        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
    }
}
