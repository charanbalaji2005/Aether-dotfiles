pragma Singleton
import Quickshell
import Quickshell.Io
import "../core"

// Quickshell ships no dedicated NetworkManager QML module (unlike Hyprland,
// Pipewire, or UPower), so this talks to `nmcli` — NetworkManager's own
// stable, documented CLI — rather than hand-rolling D-Bus calls.
Singleton {
    id: root

    property bool available: false
    property bool connected: false
    property string connectionType: "none" // "wifi" | "ethernet" | "none"
    property string ssid: ""
    property int signalStrength: 0

    Process {
        id: statusProcess
        command: ["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "device", "status"]
        stdout: StdioCollector {
            onStreamFinished: root._parseStatus(this.text)
        }
    }

    Process {
        id: wifiProcess
        command: ["nmcli", "-t", "-f", "ACTIVE,SIGNAL,SSID", "device", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: root._parseWifi(this.text)
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    function refresh() {
        statusProcess.running = true;
        wifiProcess.running = true;
    }

    function _parseStatus(text) {
        root.available = true;

        const lines = text.trim().split("\n").filter(function(l) { return l.length > 0; });
        let bestType = "none";
        let connectedFound = false;

        for (const line of lines) {
            const parts = line.split(":");
            const type = parts[0];
            const state = parts[1];
            if (state === "connected") {
                connectedFound = true;
                if (type === "ethernet") { bestType = "ethernet"; break; }
                if (type === "wifi") bestType = "wifi";
            }
        }

        root.connected = connectedFound;
        root.connectionType = connectedFound ? bestType : "none";
        EventBus.networkChanged(root.connected, root.connectionType, root.signalStrength);
    }

    function _parseWifi(text) {
        const lines = text.trim().split("\n").filter(function(l) { return l.length > 0; });
        for (const line of lines) {
            const parts = line.split(":");
            if (parts[0] === "yes") {
                root.signalStrength = parseInt(parts[1]) || 0;
                root.ssid = parts.slice(2).join(":");
                return;
            }
        }
        root.ssid = "";
        root.signalStrength = 0;
    }

    Component.onCompleted: refresh()
}
