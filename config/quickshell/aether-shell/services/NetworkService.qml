pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// NetworkManager via `nmcli` (Quickshell has no NetworkManager module).
// Every nmcli call is an argv array — SSIDs and passwords are never
// interpolated into a shell string.
//
// Polling: device status every 5 s (cheap). The Wi-Fi list is read with
// `--rescan no` so polling never triggers radio scans; a real scan happens
// only when the user opens the Wi-Fi list or presses refresh.
Singleton {
    id: root

    property bool available: false
    property bool connected: false
    property string connectionType: "none" // "wifi" | "ethernet" | "none"
    property string ssid: ""
    property int signalStrength: 0
    readonly property int signalLevel: signalStrength >= 70 ? 3 : signalStrength >= 45 ? 2 : signalStrength > 0 ? 1 : 0

    property bool wifiEnabled: false
    property bool wifiHardwareAvailable: false
    property var networks: []          // [{ ssid, signal, security, active, known }]
    property var knownConnections: []  // saved Wi-Fi connection names
    property bool scanning: false
    property string busySsid: ""
    property string lastError: ""
    property string wifiDevice: ""     // e.g. wlp2s0, from device status
    property var vpns: []              // names of active VPN / WireGuard connections

    // ── Status ──────────────────────────────────────────────────────────
    Process {
        id: statusProcess
        command: ["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION,DEVICE", "device", "status"]
        stdout: StdioCollector { onStreamFinished: root._parseStatus(this.text) }
        onExited: function(code) { if (code !== 0) root.available = false; }
    }

    Process {
        id: radioProcess
        command: ["nmcli", "-t", "-f", "WIFI-HW,WIFI", "radio"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.trim().split(":");
                root.wifiHardwareAvailable = p[0] === "enabled";
                root.wifiEnabled = p[1] === "enabled";
            }
        }
    }

    Process {
        id: wifiProcess
        property bool rescan: false
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", rescan ? "yes" : "no"]
        stdout: StdioCollector { onStreamFinished: root._parseWifi(this.text) }
        onExited: { root.scanning = false; rescan = false; }
    }

    Process {
        id: knownProcess
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = [];
                for (const line of this.text.split("\n")) {
                    const parts = root._splitTerse(line);
                    if (parts.length >= 2 && parts[1] === "802-11-wireless") names.push(parts[0]);
                }
                root.knownConnections = names;
            }
        }
    }

    Process {
        id: actionProcess
        stderr: StdioCollector {
            onStreamFinished: {
                const msg = this.text.trim();
                if (msg.length > 0) root.lastError = msg.replace(/^Error:\s*/, "");
            }
        }
        onExited: function(code) {
            if (code === 0) root.lastError = "";
            root.busySsid = "";
            root.refresh();
            root.refreshNetworks(false);
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: vpnProcess
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of this.text.split("\n")) {
                    // nmcli -t escapes ':' inside fields as '\:'; the type is the last field.
                    const i = line.lastIndexOf(":");
                    if (i < 0) continue;
                    const type = line.substring(i + 1);
                    if (type === "vpn" || type === "wireguard") out.push(line.substring(0, i).replace(/\\:/g, ":"));
                }
                if (JSON.stringify(out) !== JSON.stringify(root.vpns)) root.vpns = out;
            }
        }
    }

    function refresh() {
        statusProcess.running = true;
        vpnProcess.running = true;
        radioProcess.running = true;
        if (!wifiProcess.running) wifiProcess.running = true;
    }

    // Called when the Wi-Fi list is shown; rescan=true triggers a real scan.
    function refreshNetworks(rescan) {
        if (wifiProcess.running) return;
        wifiProcess.rescan = rescan === true;
        root.scanning = rescan === true;
        wifiProcess.running = true;
        knownProcess.running = true;
    }

    function setWifiEnabled(on) {
        root._run(["nmcli", "radio", "wifi", on ? "on" : "off"]);
        root.wifiEnabled = on; // optimistic; corrected by the next poll
    }

    function connectTo(ssid, password) {
        if (!ssid) return;
        root.busySsid = ssid;
        root.lastError = "";
        if (password && password.length > 0) {
            // NOTE: nmcli takes the passphrase as an argument; it is visible
            // in the process list for the second or two nmcli runs. See
            // SECURITY.md ("Wi-Fi passwords") for the trade-off.
            root._run(["nmcli", "device", "wifi", "connect", ssid, "password", password]);
        } else {
            // Open networks, and saved ones: NetworkManager reuses an existing
            // profile for this SSID (whatever the profile is named), so no
            // secret is needed on the command line.
            root._run(["nmcli", "device", "wifi", "connect", ssid]);
        }
    }

    function disconnect() {
        // By device: profile names don't always equal the SSID.
        if (root.wifiDevice.length > 0) root._run(["nmcli", "device", "disconnect", root.wifiDevice]);
    }

    function forget(ssid) {
        root._run(["nmcli", "connection", "delete", "id", ssid]);
    }

    function _run(argv) {
        if (actionProcess.running) {
            Logger.warn("NetworkService", "nmcli busy, ignored: " + argv.join(" "));
            return;
        }
        actionProcess.command = argv;
        actionProcess.running = true;
    }

    // nmcli -t escapes ':' inside values as '\:'.
    function _splitTerse(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line.charAt(i);
            if (c === "\\" && i + 1 < line.length) { cur += line.charAt(i + 1); i++; }
            else if (c === ":") { out.push(cur); cur = ""; }
            else cur += c;
        }
        out.push(cur);
        return out;
    }

    function _parseStatus(text) {
        root.available = true;
        let bestType = "none";
        let wifiDev = "";
        let connectedFound = false;
        for (const line of text.trim().split("\n")) {
            if (line.length === 0) continue;
            const parts = root._splitTerse(line);
            if (parts[0] === "wifi" && wifiDev.length === 0) wifiDev = parts[3] || "";
            if (parts[1] === "connected") {
                connectedFound = true;
                if (parts[0] === "ethernet") { bestType = "ethernet"; break; }
                if (parts[0] === "wifi") bestType = "wifi";
            }
        }
        root.wifiDevice = wifiDev;
        root.connected = connectedFound;
        root.connectionType = connectedFound ? bestType : "none";
        EventBus.networkChanged(root.connected, root.connectionType, root.signalStrength);
    }

    function _parseWifi(text) {
        const bySsid = {};
        let active = null;
        for (const line of text.split("\n")) {
            if (line.length === 0) continue;
            const p = root._splitTerse(line);
            const name = p[1] || "";
            if (name.length === 0) continue; // hidden networks
            const entry = {
                ssid: name,
                signal: parseInt(p[2]) || 0,
                security: p[3] || "",
                active: p[0] === "*",
                known: root.knownConnections.indexOf(name) >= 0
            };
            if (entry.active) active = entry;
            if (!bySsid[name] || bySsid[name].signal < entry.signal || entry.active) bySsid[name] = entry;
        }
        const list = Object.keys(bySsid).map(function(k) { return bySsid[k]; });
        list.sort(function(a, b) { return (b.active - a.active) || (b.known - a.known) || (b.signal - a.signal); });
        root.networks = list;
        root.ssid = active ? active.ssid : "";
        root.signalStrength = active ? active.signal : 0;
    }

    Component.onCompleted: refresh()
}
