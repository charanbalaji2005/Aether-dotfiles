import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../theme"
import "../../core"
import "../../services"

// Screen-edge activation (Settings → Gestures → Screen edges).
//
// Each enabled edge is a 2 px transparent layer strip. An action fires
// only after the pointer has *rested* against the edge for
// Config.gestures.edgeDwellMs (default 220 ms) — merely crossing it on the
// way to a scrollbar does nothing. A drag in progress (a mouse button held)
// never triggers, and an edge fires at most once until the pointer leaves.
// Strips sit on the Top layer and never reserve space. Fullscreen windows
// cover them, so games and videos are unaffected.
//
// Touchpad swipes are configured separately: they are compositor gestures
// written into compat.conf by `aether hyprland compat`.
Scope {
    id: root

    readonly property bool enabled: Config.gestures.edgesEnabled && !WindowService.fullscreenActive
    readonly property var edges: [
        { id: "left", action: Config.gestures.edgeLeft },
        { id: "right", action: Config.gestures.edgeRight },
        { id: "top", action: Config.gestures.edgeTop },
        { id: "bottom", action: Config.gestures.edgeBottom }
    ]

    // One window per (screen, enabled edge). Variants (not Repeater) is how
    // Quickshell instantiates windows from a model.
    readonly property var strips: {
        const out = [];
        if (!root.enabled) return out;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            for (const e of root.edges)
                if (e.action && e.action !== "none") out.push({ screen: screens[i], edge: e.id, action: e.action });
        return out;
    }

    Variants {
        model: root.strips
        delegate: Component {
            PanelWindow {
                id: strip
                required property var modelData
                screen: modelData.screen
                WlrLayershell.namespace: "aether-edge"
                WlrLayershell.layer: WlrLayer.Top
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                readonly property string edge: modelData.edge
                readonly property bool horiz: edge === "top" || edge === "bottom"
                anchors {
                    left: strip.edge !== "right"; right: strip.edge !== "left"
                    top: strip.edge !== "bottom"; bottom: strip.edge !== "top"
                }
                // Corners are left free (hot corners belong to apps/menus).
                margins {
                    left: strip.horiz ? 80 : 0; right: strip.horiz ? 80 : 0
                    top: strip.horiz ? 0 : 80; bottom: strip.horiz ? 0 : 80
                }
                implicitWidth: horiz ? 0 : 2
                implicitHeight: horiz ? 2 : 0

                property bool fired: false
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    onEntered: { strip.fired = false; dwell.restart(); }
                    onExited: dwell.stop()
                }
                Timer {
                    id: dwell
                    interval: Math.max(0, Config.gestures.edgeDwellMs)
                    onTriggered: {
                        if (strip.fired) return;
                        strip.fired = true;
                        ActionService.run(strip.modelData.action);
                    }
                }
            }
        }
    }
}
