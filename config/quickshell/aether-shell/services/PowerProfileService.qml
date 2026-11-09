pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// System power profile (power-saver / balanced / performance) through
// `powerprofilesctl` — the interface shared by power-profiles-daemon and
// Fedora's tuned-ppd. This is the only performance control the shell
// exposes; it never writes governors, clocks or power limits itself.
Singleton {
    id: root

    property bool available: false
    property string active: ""
    property var profiles: []
    property string lastError: ""

    readonly property bool batterySaver: active === "power-saver"
    readonly property bool performanceMode: active === "performance"

    Process {
        id: getProcess
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector { onStreamFinished: root.active = this.text.trim() }
        onExited: function(code) { root.available = code === 0; }
    }

    Process {
        id: listProcess
        command: ["powerprofilesctl", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = [];
                for (const raw of this.text.split("\n")) {
                    const s = raw.trim().replace(/^\*\s*/, "");
                    const m = s.match(/^(power-saver|balanced|performance):$/);
                    if (m) found.push(m[1]);
                }
                root.profiles = found;
            }
        }
    }

    Process {
        id: setProcess
        stderr: StdioCollector { onStreamFinished: root.lastError = this.text.trim() }
        onExited: function(code) {
            if (code === 0) root.lastError = "";
            getProcess.running = true;
        }
    }

    // External changes (e.g. firmware switching on AC unplug) are picked up
    // by a slow poll; this is one tiny process every 30 s.
    Timer {
        interval: 30000
        running: root.available
        repeat: true
        onTriggered: getProcess.running = true
    }

    function has(profile) { return root.profiles.indexOf(profile) >= 0; }

    function set(profile) {
        if (!root.available || !root.has(profile)) return;
        root.active = profile; // optimistic
        setProcess.command = ["powerprofilesctl", "set", profile];
        setProcess.running = true;
    }

    // Toggle helpers for the control centre tiles: switching a mode off
    // returns to balanced.
    function toggleBatterySaver() { set(root.batterySaver ? "balanced" : "power-saver"); }
    function togglePerformance() { set(root.performanceMode ? "balanced" : "performance"); }

    Component.onCompleted: {
        getProcess.running = true;
        listProcess.running = true;
    }
}
