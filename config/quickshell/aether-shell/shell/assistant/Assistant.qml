import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../core"
import "../../services"
import "../../components"
import "../../animation"
import "../../graphics"

// The AetherOS assistant (SUPER+Y). Optional and off by default
// (Settings → AI assistant). Replies stream in; actions the model proposes
// are shown as cards and run only when you click Run.
Scope {
    id: root

    PopupPanel {
        id: panel
        layerNamespace: "aether-assistant"
        placement: "center"
        cardWidth: Math.min(640, (screen ? screen.width : 1280) - 80)
        cardHeight: Math.min(620, (screen ? screen.height : 900) - 120)
        cardRadius: Metrics.radiusXl
        onOpened: { AssistantService.refreshStatus(false); input.forceActiveFocus(); }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Metrics.spaceLg
            spacing: Metrics.spaceMd

            RowLayout {
                Layout.fillWidth: true
                AetherIcon { width: 18; height: 18; name: "sparkle"; color: Colors.accent }
                Text { text: "Assistant"; color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeXl; font.weight: Typography.weightSemibold }
                Text {
                    Layout.fillWidth: true
                    text: Config.ai.provider + " · " + Config.ai.model + (Config.ai.localOnly ? " · local only" : "")
                    color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
                    elide: Text.ElideRight
                }
                IconButton { icon: "trash"; onClicked: AssistantService.clear() }
                IconButton { icon: "gear"; onClicked: { panel.hide(); EventBus.settingsRequested("ai"); } }
            }

            // Off: say so, and how to turn it on.
            ColumnLayout {
                visible: !AssistantService.enabled
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Metrics.spaceSm
                Item { Layout.fillHeight: true }
                Text {
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                    text: "The assistant is off. It's optional: turn it on in Settings → AI assistant. With Ollama it runs entirely on this computer."
                    color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeMd
                }
                Item { Layout.fillHeight: true }
            }

            ListView {
                id: chat
                visible: AssistantService.enabled
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Metrics.spaceSm
                model: AssistantService.messages.concat(AssistantService.busy ? [{ role: "assistant", content: AssistantService.partial || "…", streaming: true }] : [])
                onCountChanged: positionViewAtEnd()
                delegate: Column {
                    id: msg
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    spacing: 4
                    readonly property bool mine: modelData.role === "user"
                    Rectangle {
                        anchors.right: msg.mine ? parent.right : undefined
                        width: Math.min(parent.width * 0.86, body.implicitWidth + 24)
                        height: body.implicitHeight + 16
                        radius: Metrics.radiusLg
                        color: msg.mine ? Colors.accentSoft : (msg.modelData.error ? Colors.withAlpha(Colors.danger, 0.15) : Colors.withAlpha(Colors.surface, 0.8))
                        border.width: 1
                        border.color: msg.mine ? Colors.withAlpha(Colors.accent, 0.4) : Colors.border
                        TextEdit {
                            id: body
                            anchors.fill: parent; anchors.margins: 8
                            text: msg.modelData.content
                            readOnly: true; selectByMouse: true
                            wrapMode: Text.Wrap
                            textFormat: TextEdit.PlainText
                            color: msg.modelData.error ? Colors.danger : Colors.textPrimary
                            font.family: Typography.family; font.pixelSize: Typography.sizeMd
                        }
                    }
                    Repeater {
                        model: msg.modelData.actions || []
                        delegate: MotionCard {
                            id: card
                            required property var modelData
                            required property int index
                            width: Math.min(msg.width * 0.86, 440); height: 52
                            index: index
                            interactive: false
                            RowLayout {
                                anchors.fill: parent; anchors.margins: Metrics.spaceSm
                                spacing: Metrics.spaceSm
                                AetherIcon { width: 16; height: 16; name: "bolt"; color: Colors.accent }
                                Column {
                                    Layout.fillWidth: true
                                    Text { text: card.modelData.description; color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; elide: Text.ElideRight; width: parent.width }
                                    Text { text: JSON.stringify(card.modelData.args); color: Colors.textMuted; font.family: Typography.familyMono; font.pixelSize: Typography.sizeXs; elide: Text.ElideRight; width: parent.width }
                                }
                                Text {
                                    visible: !!card.modelData.state
                                    text: card.modelData.state === "ran" ? "Done" : card.modelData.state === "failed" ? "Failed" : "Declined"
                                    color: card.modelData.state === "ran" ? Colors.success : Colors.textMuted
                                    font.family: Typography.family; font.pixelSize: Typography.sizeXs
                                }
                                ChipGroup { visible: !card.modelData.state; options: [{ value: "no", label: "Decline" }]; current: ""; onSelected: AssistantService.declineAction(card.modelData, msg.index) }
                                ChipGroup { visible: !card.modelData.state; options: [{ value: "run", label: "Run" }]; current: "run"; onSelected: AssistantService.runAction(card.modelData, msg.index) }
                            }
                        }
                    }
                    Text {
                        visible: (msg.modelData.rejected || []).length > 0
                        width: parent.width; wrapMode: Text.WordWrap
                        text: "Not allowed: " + (msg.modelData.rejected || []).join("; ")
                        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: chat.count === 0
                    width: parent.width * 0.8; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                    text: "Ask about your system or ask it to do something — “switch to the developer layout”, “turn on do not disturb”, “why are my effects reduced?”. It can only propose actions; you confirm each one."
                    color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm
                }
            }

            Rectangle {
                visible: AssistantService.enabled
                Layout.fillWidth: true
                implicitHeight: 44
                radius: 22
                color: Colors.withAlpha(Colors.surface, 0.9)
                border.width: 1; border.color: input.activeFocus ? Colors.accent : Colors.border
                GlowEdge { anchors.fill: parent; radius: 22; active: AssistantService.busy; intensity: AssistantService.busy ? 0.8 : 0; visible: intensity > 0; period: 1800 }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 8
                    TextInput {
                        id: input
                        Layout.fillWidth: true
                        verticalAlignment: TextInput.AlignVCenter
                        color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeMd
                        enabled: !AssistantService.busy
                        Keys.onReturnPressed: { AssistantService.send(text); text = ""; }
                        Keys.onEscapePressed: panel.hide()
                        Accessible.role: Accessible.EditableText
                        Accessible.name: "Ask the assistant"
                        Text { anchors.verticalCenter: parent.verticalCenter; visible: input.text.length === 0; text: AssistantService.busy ? "Thinking…" : "Ask anything"; color: Colors.textMuted; font: input.font }
                    }
                    Spinner { visible: AssistantService.busy; width: 16; height: 16 }
                    IconButton { visible: AssistantService.busy; icon: "close"; onClicked: AssistantService.cancel() }
                }
            }
        }
    }

    Connections {
        target: EventBus
        function onAssistantRequested() { panel.toggle(); }
    }
    IpcHandler {
        target: "assistant"
        function toggle(): void { panel.toggle(); }
    }
}
