import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// On-screen display for volume, microphone and brightness changes.
// Volume/mic changes arrive reactively from PipeWire (any source: keys,
// pavucontrol, the bar). Brightness keys call `qs ... ipc call osd
// brightness` after brightnessctl (see keybinds.conf), since sysfs
// backlight changes can't be watched without polling.
//
// Ignores events for the first seconds after start-up so the shell doesn't
// flash an OSD while PipeWire reports its initial state.
Scope {
    id: root

    property string kind: "volume"
    property real value: 0
    property bool muted: false
    property bool shown: false
    property bool armed: false

    Timer { interval: 2500; running: true; onTriggered: root.armed = true }
    Timer { id: hideTimer; interval: 1400; onTriggered: root.shown = false }

    function show(k, v, m) {
        if (!root.armed) return;
        root.kind = k;
        root.value = Math.max(0, Math.min(1, v));
        root.muted = m;
        root.shown = true;
        hideTimer.restart();
    }

    Connections {
        target: EventBus
        function onOsdRequested(kind, value, muted) { root.show(kind, value, muted); }
    }

    Connections {
        target: BrightnessService
        function onValueChanged() { if (root.pendingBrightness) { root.pendingBrightness = false; root.show("brightness", BrightnessService.value, false); } }
    }
    property bool pendingBrightness: false
    // If the key press didn't change the value (already at 1 % / 100 %), don't
    // let a later unrelated change (e.g. the control-centre slider) pop the OSD.
    Timer { id: pendingReset; interval: 1000; onTriggered: root.pendingBrightness = false }

    PanelWindow {
        id: win
        visible: root.shown || card.opacity > 0.01
        screen: ShellState.activeScreen ? ShellState.activeScreen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
        WlrLayershell.namespace: "aether-osd"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors { bottom: true }
        margins { bottom: 80 }
        implicitWidth: 300
        implicitHeight: 56
        color: "transparent"

        GlassPanel {
            id: card
            anchors.fill: parent
            radius: Metrics.radiusPill
            tintOpacity: Math.max(0.85, Colors.glassOpacity)
            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.94
            Behavior on opacity { NumberAnimation { duration: Motion.normal } }
            Behavior on scale { NumberAnimation { duration: Motion.normal; easing.type: Motion.easeStandard } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Metrics.spaceLg
                anchors.rightMargin: Metrics.spaceLg
                spacing: Metrics.spaceMd

                AetherIcon {
                    width: 20; height: 20
                    name: root.kind === "brightness" ? "sun"
                        : root.kind === "microphone" ? (root.muted ? "mic-off" : "mic")
                        : (root.muted ? "volume-mute" : root.value > 0.5 ? "volume-high" : "volume-low")
                    color: root.muted ? Colors.danger : Colors.textPrimary
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 6
                    radius: 3
                    color: Colors.withAlpha(Colors.textMuted, 0.25)
                    Rectangle {
                        width: parent.width * (root.muted ? 0 : root.value)
                        height: parent.height
                        radius: 3
                        color: Colors.accent
                        Behavior on width { NumberAnimation { duration: Motion.fast } }
                    }
                }

                Text {
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                    text: root.muted ? "Muted" : Math.round(root.value * 100) + "%"
                    color: Colors.textSecondary
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeSm
                    font.weight: Typography.weightMedium
                }
            }
        }
    }

    IpcHandler {
        target: "osd"
        function brightness(): void { root.pendingBrightness = true; pendingReset.restart(); BrightnessService.refresh(); }
        function volume(): void { root.show("volume", AudioService.volume, AudioService.muted); }
    }
}
