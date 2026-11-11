import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → GPU & rendering: what renders the desktop, live counters, the
// GPU-pressure policy, and rendering diagnostics (files only — never wakes a
// sleeping discrete GPU).
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg
    property var render: null
    Component.onCompleted: CliService.run("render", ["render", "--json"], function(ok, d) { root.render = d; })

    Repeater {
        model: SystemMonitorService.gpusMerged
        delegate: MotionCard {
            required property var modelData
            required property int index
            Layout.fillWidth: true; implicitHeight: gcol.implicitHeight + Metrics.spaceMd * 2
            index: index; interactive: false
            ColumnLayout {
                id: gcol
                anchors.fill: parent; anchors.margins: Metrics.spaceMd
                spacing: 2
                Text { text: modelData.name + "  ·  " + modelData.kind + (modelData.source === "nvml" ? "  ·  NVML" : ""); color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeMd; font.weight: Typography.weightSemibold }
                Text {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: modelData.state === "suspended" ? "Asleep — not queried, to save power."
                        : modelData.usage === null || modelData.usage === undefined ? (modelData.note || "No counters available.")
                        : Math.round(modelData.usage * 100) + "% busy"
                          + (modelData.vramTotal ? "  ·  VRAM " + (modelData.vramUsed / 1073741824).toFixed(1) + " / " + (modelData.vramTotal / 1073741824).toFixed(1) + " GiB" : "")
                          + (modelData.tempC !== null && modelData.tempC !== undefined ? "  ·  " + Math.round(modelData.tempC) + " °C" : "")
                          + (modelData.powerW ? "  ·  " + modelData.powerW + " W" + (modelData.powerLimitW ? " of " + modelData.powerLimitW : "") : "")
                    color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm
                }
            }
        }
    }

    SectionLabel { text: "When the GPU is busy"; Layout.topMargin: Metrics.spaceSm }
    SettingRow {
        label: "Reduce effects under GPU pressure"
        description: PerformanceService.pressure.active ? "Active now: " + PerformanceService.pressure.reason : "Steps visual quality down while VRAM or GPU load stays high, then restores it gradually"
        Switch { checked: Config.effects.gpuPressure; onToggled: function(v) { Config.effects.gpuPressure = v; } }
    }
    SettingRow {
        visible: Config.effects.gpuPressure
        label: "VRAM threshold"; description: Math.round(Config.effects.vramThreshold * 100) + "% of video memory in use"
        Slider { implicitWidth: 180; from: 0.5; to: 0.99; value: Config.effects.vramThreshold; format: function(v) { return Math.round(v * 100) + "%"; }; onMoved: function(v) { Config.effects.vramThreshold = Math.round(v * 100) / 100; } }
    }
    SettingRow {
        visible: Config.effects.gpuPressure
        label: "GPU load threshold"
        Slider { implicitWidth: 180; from: 0.5; to: 0.99; value: Config.effects.gpuThreshold; format: function(v) { return Math.round(v * 100) + "%"; }; onMoved: function(v) { Config.effects.gpuThreshold = Math.round(v * 100) / 100; } }
    }

    SectionLabel { text: "Rendering"; Layout.topMargin: Metrics.spaceSm }
    Repeater {
        model: root.render ? Object.keys(root.render.qtBackends) : []
        delegate: RowLayout {
            required property string modelData
            Layout.fillWidth: true
            readonly property var b: root.render.qtBackends[modelData]
            Rectangle { width: 8; height: 8; radius: 4; color: b.available ? Colors.success : Colors.textMuted }
            Text { Layout.preferredWidth: 90; text: modelData; color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
            Text { Layout.fillWidth: true; text: b.available ? (modelData === root.render.effectiveBackend ? "in use" : "available") : b.why; color: Colors.textSecondary; wrapMode: Text.WordWrap; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
        }
    }
    Repeater {
        model: root.render ? root.render.notes : []
        delegate: Text { required property string modelData; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "• " + modelData; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
    }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "Run an app on the discrete GPU: aether gpu run <app>.  Full driver checks: aether graphics verify.  Driver probe: aether render --probe."
        color: Colors.textMuted; font.family: Typography.familyMono; font.pixelSize: Typography.sizeXs
    }
}
