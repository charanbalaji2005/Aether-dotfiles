import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → Lock screen. Timings are applied to hypridle by IdleService
// (`aether idle apply`); authentication is always PAM.
ColumnLayout {
    spacing: Metrics.spaceLg

    SettingRow {
        label: "Clock"
        ChipGroup {
            options: [{ value: "digital", label: "Digital" }, { value: "large", label: "Stacked" }, { value: "split", label: "Split" }, { value: "analog", label: "Analog" }]
            current: Config.lock.clockStyle
            onSelected: function(v) { Config.lock.clockStyle = v; }
        }
    }
    SettingRow { label: "Show the date"; Switch { checked: Config.lock.showDate; onToggled: function(v) { Config.lock.showDate = v; } } }
    SettingRow { label: "Blur the wallpaper"; Switch { checked: Config.lock.blurBackground; onToggled: function(v) { Config.lock.blurBackground = v; } } }
    SettingRow { label: "Media controls"; Switch { checked: Config.lock.showMedia; onToggled: function(v) { Config.lock.showMedia = v; } } }
    SettingRow { label: "Battery"; Switch { checked: Config.lock.showBattery; onToggled: function(v) { Config.lock.showBattery = v; } } }
    SettingRow {
        label: "Hide notification contents"
        description: "Only the number of new notifications is shown while locked"
        Switch { checked: Config.lock.hideNotificationContent; onToggled: function(v) { Config.lock.hideNotificationContent = v; } }
    }

    SectionLabel { text: "When idle"; Layout.topMargin: Metrics.spaceSm }
    Repeater {
        model: [{ key: "idleLockMinutes", label: "Lock the screen after", max: 120 },
                { key: "idleDisplayOffMinutes", label: "Turn displays off after", max: 120 },
                { key: "idleSuspendMinutes", label: "Suspend after", max: 240 }]
        delegate: SettingRow {
            id: idleRow
            required property var modelData
            label: modelData.label
            description: Config.lock[modelData.key] > 0 ? Config.lock[modelData.key] + " minutes" : "Never"
            Slider {
                implicitWidth: 180; from: 0; to: idleRow.modelData.max
                value: Config.lock[idleRow.modelData.key]
                format: function(v) { return Math.round(v) > 0 ? Math.round(v) + " min" : "never"; }
                onMoved: function(v) { Config.lock[idleRow.modelData.key] = Math.round(v); }
            }
        }
    }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "Idle actions run through hypridle (aether-idle.service). Media players and video calls that inhibit idle are respected. The screen also locks before suspend."
        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
    }
    RowLayout {
        Item { Layout.fillWidth: true }
        Rectangle {
            implicitWidth: lt.implicitWidth + 28; implicitHeight: 32; radius: 16; color: Colors.accent
            Text { id: lt; anchors.centerIn: parent; text: "Lock now to preview"; color: Colors.onAccent; font.family: Typography.family; font.pixelSize: Typography.sizeSm; font.weight: Typography.weightSemibold }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: EventBus.lockRequested() }
        }
    }
}
