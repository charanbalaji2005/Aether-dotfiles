pragma Singleton
import QtQuick
import Quickshell
import "../core"

// The fixed set of shell actions a gesture, edge, automation rule or
// keybind may trigger. Kept identical to ACTIONS in lib/aether/config.py
// (tests compare them): imported settings can only name an action id,
// never supply a command.
Singleton {
    id: root

    readonly property var actions: [
        { id: "none", label: "Nothing" },
        { id: "launcher", label: "App launcher" },
        { id: "controlcenter", label: "Control centre" },
        { id: "dashboard", label: "Dashboard" },
        { id: "notifications", label: "Notification centre" },
        { id: "overview", label: "Overview" },
        { id: "clipboard", label: "Clipboard history" },
        { id: "settings", label: "Settings" },
        { id: "powermenu", label: "Power menu" },
        { id: "lock", label: "Lock screen" },
        { id: "dock", label: "Show/hide dock" },
        { id: "wallpaper-next", label: "Next wallpaper" },
        { id: "systemcenter", label: "System centre" },
        { id: "assistant", label: "Assistant" },
        { id: "layouts", label: "Window layouts" }
    ]

    function label(id) {
        const a = root.actions.find(function(x) { return x.id === id; });
        return a ? a.label : id;
    }

    function run(id) {
        switch (id) {
        case "launcher": EventBus.launcherRequested(); return true;
        case "controlcenter": EventBus.controlCenterRequested(); return true;
        case "dashboard": EventBus.dashboardRequested(); return true;
        case "notifications": EventBus.notificationCenterRequested(); return true;
        case "overview": EventBus.overviewRequested("all"); return true;
        case "clipboard": EventBus.clipboardRequested(); return true;
        case "settings": EventBus.settingsRequested(""); return true;
        case "powermenu": EventBus.powerMenuRequested(); return true;
        case "lock": EventBus.lockRequested(); return true;
        case "dock": EventBus.dockToggleRequested(); return true;
        case "wallpaper-next": WallpaperService.nextWallpaper(); return true;
        case "systemcenter": EventBus.systemCenterRequested(""); return true;
        case "assistant": EventBus.assistantRequested(); return true;
        case "layouts": EventBus.layoutPickerRequested(); return true;
        case "none": case "": return true;
        default:
            Logger.warn("ActionService", "Unknown action '" + id + "' ignored");
            return false;
        }
    }
}
