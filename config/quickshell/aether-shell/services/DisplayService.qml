pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// Monitor information from `hyprctl -j monitors` (Hyprland's stable JSON
// IPC) and live scale changes via `hyprctl keyword monitor`.
//
// Changes made here are RUNTIME changes: they last until Hyprland reloads
// its config. Persistent layouts belong in config/hypr/monitors.conf; when
// `nwg-displays` is installed the control centre offers it, since it writes
// that file for you. The UI states this — nothing here pretends to persist.
Singleton {
    id: root

    property var monitors: []    // [{ name, description, width, height, refreshRate, scale, x, y, focused }]
    readonly property bool available: HyprlandService.available
    property bool nwgDisplaysAvailable: false

    Process {
        id: listProcess
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text);
                    root.monitors = data.map(function(m) {
                        return {
                            name: m.name,
                            description: (m.make ? m.make + " " : "") + (m.model || m.description || ""),
                            width: m.width, height: m.height,
                            refreshRate: m.refreshRate,
                            scale: m.scale,
                            x: m.x, y: m.y,
                            focused: m.focused === true
                        };
                    });
                } catch (e) {
                    Logger.warn("DisplayService", "Could not parse hyprctl monitors: " + e);
                }
            }
        }
    }

    Process {
        id: checkNwg
        command: ["sh", "-c", "command -v nwg-displays >/dev/null && echo yes || true"]
        stdout: StdioCollector { onStreamFinished: root.nwgDisplaysAvailable = this.text.trim() === "yes" }
    }

    Process {
        id: applyProcess
        onExited: listProcess.running = true
    }

    function refresh() {
        if (root.available) listProcess.running = true;
    }

    function setScale(mon, scale) {
        if (!mon || !root.available) return;
        const mode = mon.width + "x" + mon.height + "@" + Number(mon.refreshRate).toFixed(2);
        const pos = mon.x + "x" + mon.y;
        applyProcess.command = ["hyprctl", "keyword", "monitor", mon.name + "," + mode + "," + pos + "," + scale];
        applyProcess.running = true;
    }

    function openDisplaySettings() {
        if (root.nwgDisplaysAvailable) Quickshell.execDetached(["nwg-displays"]);
    }

    Connections {
        target: HyprlandService
        function onConfigReloaded() { root.refresh(); }
    }

    Component.onCompleted: {
        refresh();
        checkNwg.running = true;
    }
}
