pragma Singleton
import Quickshell
import Quickshell.Hyprland
import "../core"

// Thin, reactive wrapper around Quickshell's built-in Hyprland IPC
// integration. UI never imports Quickshell.Hyprland directly — it goes
// through here, so `available` gating and dispatch helpers live in one place.
Singleton {
    id: root

    readonly property bool available: Quickshell.isEnvSet("HYPRLAND_INSTANCE_SIGNATURE")

    readonly property var workspaces: available ? Hyprland.workspaces : []
    readonly property var monitors: available ? Hyprland.monitors : []
    readonly property var focusedWorkspace: available ? Hyprland.focusedWorkspace : null
    readonly property var focusedMonitor: available ? Hyprland.focusedMonitor : null

    function switchToWorkspace(id) {
        if (!available) {
            Logger.warn("HyprlandService", "switchToWorkspace ignored, Hyprland not detected");
            return;
        }
        Hyprland.dispatch("workspace " + id);
    }

    function closeActiveWindow() {
        if (!available) return;
        Hyprland.dispatch("killactive");
    }

    function refresh() {
        if (!available) return;
        Hyprland.refreshWorkspaces();
        Hyprland.refreshMonitors();
    }

    Component.onCompleted: {
        if (available) {
            Logger.info("HyprlandService", "Connected to Hyprland IPC");
        } else {
            Logger.warn("HyprlandService", "HYPRLAND_INSTANCE_SIGNATURE not set; Hyprland features disabled");
        }
    }
}
