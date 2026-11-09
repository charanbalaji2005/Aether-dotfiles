pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../core"

// Thin, reactive wrapper around Quickshell's built-in Hyprland IPC
// integration. UI never imports Quickshell.Hyprland directly — it goes
// through here, so `available` gating and dispatch helpers live in one place.
Singleton {
    id: root

    // Quickshell.env() is the documented accessor; an unset variable yields
    // an empty/undefined value.
    readonly property bool available: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")

    readonly property var workspaces: available ? Hyprland.workspaces : []
    readonly property var monitors: available ? Hyprland.monitors : []
    readonly property var focusedWorkspace: available ? Hyprland.focusedWorkspace : null
    readonly property var focusedMonitor: available ? Hyprland.focusedMonitor : null

    // The QScreen matching Hyprland's focused monitor (popups open there).
    readonly property var focusedScreen: {
        const name = focusedMonitor ? focusedMonitor.name : "";
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) if (screens[i].name === name) return screens[i];
        return screens.length > 0 ? screens[0] : null;
    }

    // Emitted after `hyprctl reload` / config auto-reload, so services can
    // re-apply runtime keywords (e.g. ThemeService's blur override).
    signal configReloaded()

    Connections {
        target: root.available ? Hyprland : null
        function onRawEvent(event) {
            if (event && event.name === "configreloaded") root.configReloaded();
        }
    }

    function dispatch(cmd) {
        if (!available) {
            Logger.warn("HyprlandService", "dispatch ignored, Hyprland not detected: " + cmd);
            return;
        }
        Hyprland.dispatch(cmd);
    }

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
