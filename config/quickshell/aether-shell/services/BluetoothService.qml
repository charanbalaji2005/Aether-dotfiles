pragma Singleton
import Quickshell
import Quickshell.Bluetooth
import "../core"

Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool enabled: available && adapter.enabled
    readonly property var devices: available ? adapter.devices : null

    // Discovery/pairing method names below (startDiscovery/stopDiscovery/
    // pair/forget) are a best-effort match to BlueZ's underlying D-Bus API
    // (StartDiscovery/StopDiscovery/Pair/RemoveDevice) rather than something
    // confirmed against Quickshell's own docs the way connect()/disconnect()
    // were. Every call is guarded by a typeof check, so a wrong name means
    // the button silently does nothing (logged) rather than crashing —
    // same fail-safe pattern used for the lock screen's PAM integration.
    // This is NOT security-sensitive the way PAM is (worst case: a button
    // doesn't work), so the bar is lower, but it's still unverified.
    readonly property bool discovering: available && adapter.discovering === true

    function toggle() {
        if (!available) return;
        adapter.enabled = !adapter.enabled;
    }

    function startDiscovery() {
        if (!available) return;
        if (typeof adapter.startDiscovery === "function") {
            adapter.startDiscovery();
        } else {
            Logger.warn("BluetoothService", "startDiscovery() not available on this Quickshell version");
        }
    }

    function stopDiscovery() {
        if (!available) return;
        if (typeof adapter.stopDiscovery === "function") {
            adapter.stopDiscovery();
        } else {
            Logger.warn("BluetoothService", "stopDiscovery() not available on this Quickshell version");
        }
    }

    function connectDevice(device) {
        if (device && typeof device.connect === "function") {
            device.connect();
        } else {
            Logger.warn("BluetoothService", "connect() not available on this device/Quickshell version");
        }
    }

    function disconnectDevice(device) {
        if (device && typeof device.disconnect === "function") {
            device.disconnect();
        } else {
            Logger.warn("BluetoothService", "disconnect() not available on this device/Quickshell version");
        }
    }

    function pairDevice(device) {
        if (device && typeof device.pair === "function") {
            device.pair();
        } else {
            Logger.warn("BluetoothService", "pair() not available on this device/Quickshell version");
        }
    }

    function forgetDevice(device) {
        if (device && typeof device.forget === "function") {
            device.forget();
        } else if (adapter && typeof adapter.removeDevice === "function") {
            adapter.removeDevice(device);
        } else {
            Logger.warn("BluetoothService", "no forget/removeDevice API available on this Quickshell version");
        }
    }
}

