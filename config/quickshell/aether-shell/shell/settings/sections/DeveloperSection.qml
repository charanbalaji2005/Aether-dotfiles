import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"
import "../../../graphics"

// Settings → Developer: diagnostics, logs, safe mode, internals.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg
    property string logText: ""

    SettingRow {
        label: "Safe mode"
        description: PerformanceService.safeMode ? "On: shaders, particles, parallax, video wallpaper and automation are off" : "Off"
        ChipGroup {
            options: [{ value: PerformanceService.safeMode ? "off" : "on", label: PerformanceService.safeMode ? "Leave safe mode" : "Enter safe mode" }]; current: ""
            onSelected: function(v) { CliService.run("safe", ["safe-mode", v], function() { PerformanceService.reprobe(); }); }
        }
    }
    InfoGrid {
        rows: [
            ["Quality tier", PerformanceService.tier],
            ["Motion profile", Config.general.motionProfile + (Motion.reducedMotion ? " (reduced)" : "")],
            ["Shader source", Effects.shaderDir ? Effects.shaderDir : "bundled (graphics/shaders)"],
            ["Failed shaders", Object.keys(ShaderLibrary.failed).join(", ") || "none"],
            ["Running animations", String(AnimationCoordinator.active)],
            ["Average frame (while animating)", AnimationCoordinator.averageFrameMs > 0 ? AnimationCoordinator.averageFrameMs.toFixed(1) + " ms" : "not measured yet"],
            ["Telemetry", SystemMonitorService.source],
            ["Windows tracked", String(WindowService.clients.length)],
            ["Config schema", String(Config.meta.schemaVersion)]
        ]
    }
    SectionLabel { text: "Recent log (redacted)"; Layout.topMargin: Metrics.spaceSm }
    ChipGroup { options: [{ value: "l", label: "Load" }]; current: ""; onSelected: logProc.running = true }
    Rectangle {
        Layout.fillWidth: true; Layout.preferredHeight: 180
        radius: Metrics.radiusMd; color: Colors.withAlpha(Colors.bg0, 0.7); border.width: 1; border.color: Colors.border
        Flickable {
            anchors.fill: parent; anchors.margins: 8; clip: true; contentHeight: lt.implicitHeight
            Text { id: lt; width: parent.width; text: root.logText || "—"; wrapMode: Text.WrapAnywhere; color: Colors.textSecondary; font.family: Typography.familyMono; font.pixelSize: Typography.sizeXs }
        }
    }
    Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "More: aether diagnostics · aether logs --shell · aether render --probe · journalctl --user -u aether-shell"; color: Colors.textMuted; font.family: Typography.familyMono; font.pixelSize: Typography.sizeXs }

    LogProcess { id: logProc; onDone: function(t) { root.logText = t; } }

    component InfoGrid: GridLayout {
        property var rows: []
        columns: 2; columnSpacing: Metrics.spaceLg; rowSpacing: 4
        Layout.fillWidth: true
        Repeater {
            model: parent.rows.length * 2
            delegate: Text {
                required property int index
                readonly property var r: parent.rows[Math.floor(index / 2)]
                text: index % 2 === 0 ? r[0] : r[1]
                color: index % 2 === 0 ? Colors.textMuted : Colors.textPrimary
                font.family: Typography.family; font.pixelSize: Typography.sizeSm
                Layout.fillWidth: index % 2 === 1
                elide: Text.ElideRight
            }
        }
    }
}
