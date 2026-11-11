import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → AI assistant. Off by default; local-only by default. API keys
// go straight to the desktop keyring (never config.json, never logs).
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg
    property string keyMessage: ""
    Component.onCompleted: AssistantService.refreshStatus(false)

    SettingRow {
        label: "Enable the assistant"
        description: "Open it with SUPER+Y. It can only propose actions from a fixed list; you confirm each one."
        Switch { checked: Config.ai.enabled; onToggled: function(v) { Config.ai.enabled = v; } }
    }
    SettingRow {
        label: "Provider"
        SegmentedControl {
            options: [{ value: "ollama", label: "Ollama (local)" }, { value: "openai", label: "OpenAI-compatible" }]
            current: Config.ai.provider
            onSelected: function(v) { Config.ai.provider = v; if (v === "ollama" && Config.ai.endpoint.indexOf(":11434") < 0) Config.ai.endpoint = "http://127.0.0.1:11434"; }
        }
    }
    SettingRow {
        label: "Endpoint"
        description: AssistantService.status && AssistantService.status.endpointProblem ? AssistantService.status.endpointProblem : "llama.cpp, LM Studio, vLLM, LocalAI, OpenAI, OpenRouter… use the OpenAI-compatible provider"
        Rectangle {
            implicitWidth: 260; implicitHeight: 30; radius: 15
            color: Colors.withAlpha(Colors.surface, 0.9); border.width: 1; border.color: ep.activeFocus ? Colors.accent : Colors.border
            TextInput { id: ep; anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; verticalAlignment: TextInput.AlignVCenter; text: Config.ai.endpoint
                        color: Colors.textPrimary; font.family: Typography.familyMono; font.pixelSize: Typography.sizeXs
                        onEditingFinished: { Config.ai.endpoint = text.trim(); AssistantService.refreshStatus(false); } }
        }
    }
    SettingRow {
        label: "Model"
        RowLayout {
            Rectangle {
                implicitWidth: 180; implicitHeight: 30; radius: 15
                color: Colors.withAlpha(Colors.surface, 0.9); border.width: 1; border.color: md.activeFocus ? Colors.accent : Colors.border
                TextInput { id: md; anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; verticalAlignment: TextInput.AlignVCenter; text: Config.ai.model
                            color: Colors.textPrimary; font.family: Typography.familyMono; font.pixelSize: Typography.sizeXs
                            validator: RegularExpressionValidator { regularExpression: /[\w.:\/+-]{1,128}/ }
                            onEditingFinished: Config.ai.model = text.trim() }
            }
            ChipGroup { options: [{ value: "t", label: "Test connection" }]; current: ""; onSelected: AssistantService.refreshStatus(true) }
        }
    }
    ChipGroup {
        visible: AssistantService.status && AssistantService.status.models && AssistantService.status.models.length > 0
        options: AssistantService.status && AssistantService.status.models ? AssistantService.status.models.slice(0, 12).map(function(m) { return { value: m, label: m }; }) : []
        current: Config.ai.model
        onSelected: function(v) { Config.ai.model = v; }
    }
    Text {
        visible: AssistantService.status !== null && AssistantService.status.reachable !== null && AssistantService.status.reachable !== undefined
        text: AssistantService.status && AssistantService.status.reachable ? "Connected." : (AssistantService.status && AssistantService.status.error ? AssistantService.status.error : "")
        color: AssistantService.status && AssistantService.status.reachable ? Colors.success : Colors.danger; font.family: Typography.family; font.pixelSize: Typography.sizeXs
    }
    SettingRow {
        label: "Local only"
        description: "Refuse any endpoint that isn't this computer. Turn off only to use a remote service (https required)."
        Switch { checked: Config.ai.localOnly; onToggled: function(v) { Config.ai.localOnly = v; AssistantService.refreshStatus(false); } }
    }
    SettingRow {
        visible: Config.ai.provider === "openai"
        label: "API key"
        description: AssistantService.status && AssistantService.status.keyStored ? "Stored in your keyring" : (AssistantService.status && !AssistantService.status.keyring ? "No keyring tool (sudo dnf install libsecret)" : "None stored")
        RowLayout {
            Rectangle {
                implicitWidth: 170; implicitHeight: 30; radius: 15
                color: Colors.withAlpha(Colors.surface, 0.9); border.width: 1; border.color: key.activeFocus ? Colors.accent : Colors.border
                TextInput { id: key; anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password; color: Colors.textPrimary; font.pixelSize: Typography.sizeSm }
            }
            ChipGroup {
                options: [{ value: "s", label: "Save to keyring" }]; current: ""
                onSelected: { KeyringService.store(Config.ai.provider, key.text, function(ok, err) { root.keyMessage = ok ? "Saved." : err; AssistantService.refreshStatus(false); }); key.text = ""; }
            }
        }
    }
    Text { visible: root.keyMessage.length > 0; text: root.keyMessage; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
    SectionLabel { text: "Privacy"; Layout.topMargin: Metrics.spaceSm }
    SettingRow { label: "Share a system summary with the model"; description: "GPU, memory and quality recommendation, so it can answer questions about this computer"; Switch { checked: Config.ai.shareSystemInfo; onToggled: function(v) { Config.ai.shareSystemInfo = v; } } }
    SettingRow { label: "Keep conversation history"; description: "Stored only on this computer, redacted (aether ai history --clear)"; Switch { checked: Config.ai.keepHistory; onToggled: function(v) { Config.ai.keepHistory = v; } } }
}
