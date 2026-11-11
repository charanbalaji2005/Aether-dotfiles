import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"
import "../../../graphics"
import "../../../animation"

// Settings → Effects & motion. "Automatic" lets PerformanceService pick the
// quality from the hardware, power state and measured frame pacing; the
// current decision and its reasons are shown live below.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg

    SettingRow {
        label: "Visual quality"
        description: "Eco: no shaders or ambient effects · Balanced: glass and transitions · Ultra: particles and richer lighting"
        SegmentedControl {
            options: [{ value: "auto", label: "Automatic" }, { value: "eco", label: "Eco" }, { value: "balanced", label: "Balanced" }, { value: "ultra", label: "Ultra" }]
            current: Config.effects.quality
            onSelected: function(v) { Config.effects.quality = v; }
        }
    }

    // Live decision.
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: why.implicitHeight + Metrics.spaceMd * 2
        radius: Metrics.radiusMd
        color: Colors.withAlpha(Colors.surface, 0.6)
        border.width: 1; border.color: Colors.border
        ColumnLayout {
            id: why
            anchors.fill: parent; anchors.margins: Metrics.spaceMd
            spacing: 2
            Text { text: "Running at: " + PerformanceService.tier + (PerformanceService.safeMode ? "  (safe mode)" : ""); color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; font.weight: Typography.weightSemibold }
            Repeater {
                model: PerformanceService.reasons
                delegate: Text { required property string modelData; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "• " + modelData; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
            }
            Text {
                visible: Object.keys(ShaderLibrary.failed).length > 0
                text: "Shaders that failed to load (using fallbacks): " + Object.keys(ShaderLibrary.failed).join(", ") + ". Rebuild them with scripts/build-shaders.sh."
                color: Colors.warning; font.family: Typography.family; font.pixelSize: Typography.sizeXs
                Layout.fillWidth: true; wrapMode: Text.WordWrap
            }
        }
    }

    SettingRow {
        label: "Adaptive quality"
        description: "Step down a level when animation frames run late (measured only while the shell animates)"
        Switch { checked: Config.effects.adaptive; onToggled: function(v) { Config.effects.adaptive = v; } }
    }
    SettingRow {
        label: "Shader materials"
        description: "Frosted grain, pointer light and transitions. Off = flat glass, still translucent"
        Switch { checked: Config.effects.shaders; onToggled: function(v) { Config.effects.shaders = v; } }
    }
    SettingRow {
        label: "Glowing edges"
        description: "A light that travels around the island and focused panels"
        Switch { checked: Config.effects.glow; onToggled: function(v) { Config.effects.glow = v; } }
    }
    SettingRow {
        label: "Ambient particles"
        description: "Used by the wallpaper's ambient layer; Ultra quality only, paused under fullscreen apps"
        Switch { checked: Config.effects.particles; onToggled: function(v) { Config.effects.particles = v; } }
    }

    SectionLabel { text: "Motion"; Layout.topMargin: Metrics.spaceSm }
    SettingRow {
        label: "Physics springs"
        description: "Interruptible spring motion. Off = short eased animations"
        Switch { checked: Config.effects.springs; onToggled: function(v) { Config.effects.springs = v; } }
    }
    SettingRow {
        label: "Reduce motion"
        description: "Turns every animation into an instant change"
        Switch { checked: Config.general.reducedMotion; onToggled: function(v) { Config.general.reducedMotion = v; } }
    }
    SettingRow {
        label: "Animation speed"
        description: Config.general.animationSpeed.toFixed(2) + "×"
        Slider { implicitWidth: 180; from: 0.5; to: 2.0; value: Config.general.animationSpeed; format: function(v) { return v.toFixed(2) + "×"; }; onMoved: function(v) { Config.general.animationSpeed = Math.round(v * 20) / 20; } }
    }

    // A playground to feel the settings.
    SectionLabel { text: "Try it"; Layout.topMargin: Metrics.spaceSm }
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 90
        property bool flip: false
        SpringValue { id: demo; preset: "bouncy"; target: parent.flip ? 1 : 0 }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 6; radius: 3
            color: Colors.withAlpha(Colors.textMuted, 0.2)
        }
        GlassPanel {
            id: puck
            width: 72; height: 72; radius: 36
            anchors.verticalCenter: parent.verticalCenter
            x: (parent.width - width) * demo.value
            scale: 1 + Math.min(0.25, Math.abs(demo.velocity) * 0.04)
            focused: true
        }
        GlowEdge { anchors.fill: puck; radius: 36; active: demo.running }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.flip = !parent.flip }
        Text { anchors.right: parent.right; anchors.bottom: parent.bottom; text: "click to fling"; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
    }
}
