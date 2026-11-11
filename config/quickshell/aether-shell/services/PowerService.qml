pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import "../core"

Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool available: device !== null && device.isLaptopBattery === true

    // Always 0-100 for the UI. Quickshell's UPowerDevice.percentage is a 0-1
    // fraction; normalise here so every consumer can rely on 0-100 (a raw
    // value above 1 is already a percentage and is passed through).
    readonly property real percentage: {
        if (!available) return 0;
        const p = device.percentage;
        return p <= 1.0 ? p * 100 : p;
    }
    readonly property int state: available ? device.state : UPowerDeviceState.Unknown
    readonly property bool charging: available && state === UPowerDeviceState.Charging
    readonly property bool fullyCharged: available && state === UPowerDeviceState.FullyCharged
    readonly property int timeToEmpty: available ? device.timeToEmpty : 0
    readonly property int timeToFull: available ? device.timeToFull : 0

    function formattedTimeRemaining() {
        const seconds = charging ? timeToFull : timeToEmpty;
        if (!seconds || seconds <= 0) return "";
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        return hours > 0 ? (hours + "h " + minutes + "m") : (minutes + "m");
    }

    // Health (full capacity vs design capacity) — only where UPower reports
    // it; -1 otherwise. Read defensively: older Quickshell builds lack these.
    readonly property real health: available && device.healthSupported === true && typeof device.healthPercentage === "number"
        ? device.healthPercentage : -1
    // Watts in/out, when the firmware reports it.
    readonly property real energyRate: available && typeof device.changeRate === "number" ? Math.abs(device.changeRate) : 0

    // "normal" | "low" | "critical" | "charging" | "full" — thresholds from
    // Settings → Battery. Drives icon colour and the alerts below.
    readonly property string level: !available ? "normal"
        : fullyCharged ? "full"
        : charging ? "charging"
        : percentage <= Config.battery.criticalThreshold ? "critical"
        : percentage <= Config.battery.lowThreshold ? "low"
        : "normal"

    // Alerts fire once per crossing. Hysteresis: re-armed only after the
    // battery climbs 3 points above the threshold (or starts charging), so
    // a level hovering at 20 % doesn't notify repeatedly.
    property bool _lowArmed: true
    property bool _criticalArmed: true
    property bool _fullArmed: true

    onPercentageChanged: {
        EventBus.batteryChanged(root.percentage, root.charging ? "charging" : "discharging");
        root._checkAlerts();
    }
    onChargingChanged: {
        if (root.charging) { root._lowArmed = true; root._criticalArmed = true; }
        else root._fullArmed = true;
        root._checkAlerts();
    }
    onFullyChargedChanged: root._checkAlerts()

    function _checkAlerts() {
        if (!root.available) return;
        const p = root.percentage, low = Config.battery.lowThreshold, crit = Config.battery.criticalThreshold;
        if (!root.charging) {
            if (p <= crit && root._criticalArmed) {
                root._criticalArmed = false; root._lowArmed = false;
                EventBus.notificationRequested("Battery critically low", Math.round(p) + "% remaining" + (root.formattedTimeRemaining() ? " (" + root.formattedTimeRemaining() + ")" : "") + ". Connect a charger now.", "critical");
                EventBus.islandEvent("battery", { text: "Battery critical", level: p, charging: false });
            } else if (p <= low && root._lowArmed && Config.battery.notifyLow) {
                root._lowArmed = false;
                EventBus.notificationRequested("Battery low", Math.round(p) + "% remaining" + (root.formattedTimeRemaining() ? " (" + root.formattedTimeRemaining() + ")" : ""), "normal");
                EventBus.islandEvent("battery", { text: "Battery low", level: p, charging: false });
            }
            if (p > low + 3) root._lowArmed = true;
            if (p > crit + 3) root._criticalArmed = true;
        }
        if ((root.fullyCharged || p >= 99.5) && root._fullArmed && Config.battery.notifyFull && !ShellState.onBattery) {
            root._fullArmed = false;
            EventBus.notificationRequested("Battery fully charged", "You can unplug the charger.", "low");
        }
    }
}
