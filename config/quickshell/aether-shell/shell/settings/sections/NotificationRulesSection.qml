import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Per-app notification rules (shown under Settings → Notifications).
// Apps appear here once they've sent a notification.
ColumnLayout {
    spacing: Metrics.spaceMd
    SectionLabel { text: "Per app"; Layout.topMargin: Metrics.spaceSm }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "Priority: shown and heard even in Do Not Disturb, and surfaced in the island. Mute: kept in history only."
        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
    }
    Repeater {
        model: NotificationService.knownApps
        delegate: RowLayout {
            required property string modelData
            Layout.fillWidth: true
            readonly property var rule: NotificationService.ruleFor(modelData)
            Text { Layout.fillWidth: true; text: modelData; color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; elide: Text.ElideRight }
            ChipGroup {
                options: [{ value: "normal", label: "Normal" }, { value: "priority", label: "Priority" }, { value: "mute", label: "Mute" }]
                current: parent.rule.mode
                onSelected: function(v) { NotificationService.setRule(parent.modelData, v, parent.rule.sound !== false); }
            }
            AetherIcon {
                width: 16; height: 16
                name: parent.rule.sound === false ? "volume-mute" : "volume-high"
                color: parent.rule.sound === false ? Colors.textMuted : Colors.textSecondary
                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: NotificationService.setRule(parent.parent.modelData, parent.parent.rule.mode, parent.parent.rule.sound === false) }
            }
        }
    }
    Text { visible: NotificationService.knownApps.length === 0; text: "No app has sent a notification yet."; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
}
