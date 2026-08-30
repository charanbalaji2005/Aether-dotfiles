pragma Singleton
import Quickshell
import Quickshell.Services.UPower
import "../core"

Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool available: device !== null && device.isLaptopBattery === true

    readonly property real percentage: available ? device.percentage : 0
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
