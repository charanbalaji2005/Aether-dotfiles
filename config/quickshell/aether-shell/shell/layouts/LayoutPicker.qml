import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../core"
import "../../services"
import "../../components"
import "../../animation"

// Smart layouts (SUPER+G). Pick a layout, see exactly what it will do on
// this monitor — which open window goes where, what gets launched, what is
// skipped and why — then apply it. Every placement is undoable.
Scope {
    id: root

    PopupPanel {
        id: panel
        layerNamespace: "aether-layouts"
        placement: "center"
        cardWidth: Math.min(760, (screen ? screen.width : 1280) - 80)
        cardHeight: Math.min(520, (screen ? screen.height : 900) - 140)
        cardRadius: Metrics.radiusXl

        property string selected: "developer"
        property bool launchMissing: true
        property string saveName: ""

        onOpened: { LayoutService.refresh(); LayoutService.previewLayout(selected); }
        onSelectedChanged: if (open) LayoutService.previewLayout(selected)

        RowLayout {
            anchors.fill: parent
            anchors.margins: Metrics.spaceXl
            spacing: Metrics.spaceXl

            ColumnLayout {
                Layout.preferredWidth: 250
                Layout.fillHeight: true
                spacing: Metrics.spaceSm
                Text { text: "Window layouts"; color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeXl; font.weight: Typography.weightBold }
                ListView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true; spacing: 6
                    model: LayoutService.layouts
                    delegate: MotionCard {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: 58
                        index: index
                        shown: panel.open
                        selected: panel.selected === modelData.name
                        onClicked: panel.selected = modelData.name
                        RowLayout {
                            anchors.fill: parent; anchors.margins: Metrics.spaceSm
                            spacing: Metrics.spaceSm
                            LayoutGlyph { slots: modelData.slots; Layout.preferredWidth: 54; Layout.preferredHeight: 34 }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 0
                                Text { text: modelData.label + (modelData.builtin ? "" : "  ·  yours"); color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; font.weight: Typography.weightSemibold }
                                Text { Layout.fillWidth: true; text: modelData.summary; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs; elide: Text.ElideRight }
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 30; radius: 15
                        color: Colors.withAlpha(Colors.surface, 0.9); border.width: 1; border.color: nameIn.activeFocus ? Colors.accent : Colors.border
                        TextInput {
                            id: nameIn
                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm
                            validator: RegularExpressionValidator { regularExpression: /[a-z0-9][a-z0-9-]{0,39}/ }
                            onTextChanged: panel.saveName = text
                        }
                        Text { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; visible: nameIn.text.length === 0; text: "save current as…"; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
                    }
                    IconButton { icon: "plus"; enabledState: panel.saveName.length > 0; onClicked: { LayoutService.saveCurrent(panel.saveName); nameIn.text = ""; } }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Metrics.spaceMd

                readonly property var p: LayoutService.preview
                Text {
                    text: parent.p && parent.p.ok ? "Preview on " + parent.p.monitor + " · workspace " + parent.p.workspace : "Preview"
                    color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeMd
                }
                // Scaled screen with the planned regions.
                Rectangle {
                    id: screenBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: width * (parent.p && parent.p.area ? parent.p.area.h / Math.max(1, parent.p.area.w) : 0.5625)
                    radius: Metrics.radiusMd
                    color: Colors.withAlpha(Colors.bg0, 0.7)
                    border.width: 1; border.color: Colors.border
                    readonly property var area: parent.p && parent.p.area ? parent.p.area : null
                    Repeater {
                        model: parent.parent.p && parent.parent.p.slots ? parent.parent.p.slots : []
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property var a: screenBox.area
                            x: a ? (modelData.x - a.x) / a.w * screenBox.width : 0
                            y: a ? (modelData.y - a.y) / a.h * screenBox.height : 0
                            width: a ? modelData.w / a.w * screenBox.width : 0
                            height: a ? modelData.h / a.h * screenBox.height : 0
                            radius: Metrics.radiusSm
                            color: modelData.skip ? Colors.withAlpha(Colors.textMuted, 0.12) : Colors.withAlpha(Colors.accent, modelData.window ? 0.28 : 0.14)
                            border.width: 1
                            border.color: modelData.skip ? Colors.border : Colors.accent
                            Reveal {
                                anchors.fill: parent
                                index: index
                                shown: panel.open
                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width - 8
                                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.role; color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; font.weight: Typography.weightSemibold; font.capitalization: Font.Capitalize }
                                    Text {
                                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                                        text: modelData.skip ? modelData.skip : modelData.window ? "move " + (modelData.window.class || "window") : "launch " + modelData.launch[0]
                                        color: modelData.skip ? Colors.warning : Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeXs
                                    }
                                }
                            }
                        }
                    }
                    Spinner { anchors.centerIn: parent; visible: CliService.isBusy("layout-preview"); width: 20; height: 20 }
                    Text {
                        anchors.centerIn: parent; width: parent.width - 40
                        visible: !CliService.isBusy("layout-preview") && LayoutService.error.length > 0
                        text: LayoutService.error; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm
                    }
                }
                SettingRow {
                    label: "Open missing apps"
                    description: "Launch the first installed app for regions with no matching window"
                    Switch { checked: panel.launchMissing; onToggled: function(v) { panel.launchMissing = v; } }
                }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        text: "Windows are floated into their regions. Undo restores their previous tiling or position."
                        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
                    }
                    IconButton { icon: "refresh"; onClicked: LayoutService.undo() }
                    Rectangle {
                        implicitWidth: applyText.implicitWidth + 28; implicitHeight: 34; radius: 17
                        color: Colors.accent
                        opacity: LayoutService.preview && LayoutService.preview.ok ? 1 : 0.4
                        Text { id: applyText; anchors.centerIn: parent; text: "Apply layout"; color: Colors.onAccent; font.family: Typography.family; font.pixelSize: Typography.sizeSm; font.weight: Typography.weightSemibold }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            enabled: LayoutService.preview && LayoutService.preview.ok
                            onClicked: { LayoutService.apply(panel.selected, panel.launchMissing); panel.hide(); }
                        }
                    }
                }
            }
        }
    }

    // Miniature of a layout's slots.
    component LayoutGlyph: Item {
        property var slots: []
        Rectangle { anchors.fill: parent; radius: 4; color: Colors.withAlpha(Colors.bg0, 0.6); border.width: 1; border.color: Colors.border }
        Repeater {
            model: parent.slots
            delegate: Rectangle {
                required property var modelData
                x: modelData.x * parent.width + 1.5; y: modelData.y * parent.height + 1.5
                width: modelData.w * parent.width - 3; height: modelData.h * parent.height - 3
                radius: 2
                color: Colors.withAlpha(Colors.accent, 0.45)
            }
        }
    }

    Connections {
        target: EventBus
        function onLayoutPickerRequested() { panel.toggle(); }
    }
    IpcHandler {
        target: "layouts"
        function toggle(): void { panel.toggle(); }
        function apply(name: string): void { LayoutService.apply(name, true); }
        function undo(): void { LayoutService.undo(); }
    }
}
