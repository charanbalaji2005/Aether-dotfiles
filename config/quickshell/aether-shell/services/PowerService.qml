pragma Singleton
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

    onPercentageChanged: EventBus.batteryChanged(root.percentage, root.charging ? "charging" : "discharging")
}
