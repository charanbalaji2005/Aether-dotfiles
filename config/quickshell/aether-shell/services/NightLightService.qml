pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// Night light through `hyprsunset` (the Hyprland project's own colour-
// temperature tool). On = a hyprsunset process at the configured
// temperature; off = no hyprsunset process, which restores the identity
// gamma. Unavailable (and hidden) when hyprsunset isn't installed.
Singleton {
    id: root

    property bool available: false
    property bool active: false
    readonly property int temperature: Config.nightLight.temperature || 4500

    Process {
        id: checkProcess
        command: ["sh", "-c", "command -v hyprsunset >/dev/null && echo yes; pgrep -x hyprsunset >/dev/null && echo running; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.available = this.text.indexOf("yes") >= 0;
                root.active = this.text.indexOf("running") >= 0;
            }
        }
    }

    Process {
        id: stopProcess
        command: ["pkill", "-x", "hyprsunset"]
        onExited: if (root._restartAfterStop) { root._restartAfterStop = false; root._start(); }
    }

    property bool _restartAfterStop: false

    function _start() {
        Quickshell.execDetached(["hyprsunset", "-t", String(root.temperature)]);
        root.active = true;
    }

    function enable() {
        if (!root.available) return;
        if (root.active) { root._restartAfterStop = true; stopProcess.running = true; return; }
        root._start();
    }

    function disable() {
        stopProcess.running = true;
        root.active = false;
    }

    function toggle() {
        if (root.active) disable(); else enable();
    }

    // Applying a new temperature while active restarts hyprsunset with it.
    onTemperatureChanged: if (root.active) enable()

    Component.onCompleted: checkProcess.running = true
}
