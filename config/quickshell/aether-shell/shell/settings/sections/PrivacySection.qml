import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → Privacy & security.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg
    property var auditLog: []
    property string excludeDraft: ""
    Component.onCompleted: { SystemService.loadSecurity(); CliService.run("audit", ["logs", "--audit", "--lines", "12", "--json"], function(ok, d) { if (ok) root.auditLog = d.reverse(); }); }

    SectionLabel { text: "Right now" }
    RowLayout {
        spacing: Metrics.spaceLg
        Repeater {
            model: [{ l: "Microphone", on: PrivacyService.micInUse, who: PrivacyService.micUsers }, { l: "Camera", on: PrivacyService.cameraInUse, who: PrivacyService.cameraUsers }]
            delegate: RowLayout {
                required property var modelData
                Rectangle { width: 10; height: 10; radius: 5; color: modelData.on ? Colors.warning : Colors.withAlpha(Colors.textMuted, 0.4) }
                Text { text: modelData.l + (modelData.on ? ": " + modelData.who.join(", ") : ": not in use"); color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
            }
        }
    }
    Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Detected through PipeWire. Apps that open a camera directly (V4L2) aren't visible here."; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs }

    SectionLabel { text: "Clipboard"; Layout.topMargin: Metrics.spaceSm }
    SettingRow {
        label: "Clear history automatically"
        description: Config.privacy.clipboardRetentionHours > 0 ? "Every " + Config.privacy.clipboardRetentionHours + " hours" : "Never (keep until cleared)"
        Slider { implicitWidth: 180; from: 0; to: 168; value: Config.privacy.clipboardRetentionHours; format: function(v) { return Math.round(v) > 0 ? Math.round(v) + " h" : "never"; }; onMoved: function(v) { Config.privacy.clipboardRetentionHours = Math.round(v); } }
    }
    Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Passwords copied from password managers that mark them secret (KeePassXC, Bitwarden, …) are never stored."; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
    SettingRow {
        label: "Never store copies from"
        description: (Config.privacy.clipboardExcludeApps || []).length ? (Config.privacy.clipboardExcludeApps || []).join(", ") : "No apps excluded (window class, e.g. org.keepassxc.KeePassXC)"
        RowLayout {
            Rectangle {
                implicitWidth: 170; implicitHeight: 30; radius: 15
                color: Colors.withAlpha(Colors.surface, 0.9); border.width: 1; border.color: ex.activeFocus ? Colors.accent : Colors.border
                TextInput { id: ex; anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; verticalAlignment: TextInput.AlignVCenter
                            color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm
                            validator: RegularExpressionValidator { regularExpression: /[\w.+-]{0,128}/ } }
            }
            IconButton { icon: "plus"; onClicked: { if (ex.text) { Config.privacy.clipboardExcludeApps = (Config.privacy.clipboardExcludeApps || []).concat([ex.text]); ex.text = ""; } } }
            IconButton { icon: "trash"; onClicked: Config.privacy.clipboardExcludeApps = [] }
        }
    }
    ChipGroup { options: [{ value: "wipe", label: "Clear clipboard history now" }]; current: ""; onSelected: ClipboardService.wipe() }

    SectionLabel { text: "Notifications and search"; Layout.topMargin: Metrics.spaceSm }
    SettingRow { label: "Notification sounds"; Switch { checked: Config.privacy.notificationSounds; onToggled: function(v) { Config.privacy.notificationSounds = v; } } }
    SettingRow { label: "Hide notification contents on the lock screen"; Switch { checked: Config.lock.hideNotificationContent; onToggled: function(v) { Config.lock.hideNotificationContent = v; } } }
    SettingRow {
        label: "Remember launcher searches"; description: (Config.launcher.history || []).length + " remembered (commands and file paths are never stored)"
        RowLayout {
            Switch { checked: Config.launcher.historyLimit > 0; onToggled: function(v) { Config.launcher.historyLimit = v ? 20 : 0; if (!v) Config.launcher.history = []; } }
            IconButton { icon: "trash"; onClicked: Config.launcher.history = [] }
        }
    }

    SectionLabel { text: "System security (read-only)"; Layout.topMargin: Metrics.spaceSm }
    Repeater {
        model: SystemService.security ? SystemService.security.items : []
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            Rectangle { width: 8; height: 8; radius: 4; color: modelData.level === "pass" ? Colors.success : modelData.level === "warn" ? Colors.warning : Colors.info }
            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: modelData.label + ": " + modelData.value + (modelData.detail ? " — " + modelData.detail : ""); color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
        }
    }

    SectionLabel { text: "Audit log (actions taken for you)"; Layout.topMargin: Metrics.spaceSm }
    Repeater {
        model: root.auditLog
        delegate: Text { required property var modelData; Layout.fillWidth: true; elide: Text.ElideRight; text: (modelData.time || "").substring(11, 19) + "  " + modelData.actor + "  " + modelData.action + "  " + JSON.stringify(modelData.args || {}); color: Colors.textMuted; font.family: Typography.familyMono; font.pixelSize: Typography.sizeXs }
    }
    Text { visible: root.auditLog.length === 0; text: "Nothing recorded yet. Full log: aether logs --audit"; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
}
