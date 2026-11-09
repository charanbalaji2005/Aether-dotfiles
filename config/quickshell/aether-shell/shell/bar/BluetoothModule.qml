import QtQuick
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// Bluetooth status. Click opens the device manager (shell/bluetooth/);
// right-click toggles the adapter's power.
Capsule {
    id: root
    visible: BluetoothService.available && Config.bar.showBluetooth
    implicitWidth: implicitHeight
    onClicked: EventBus.bluetoothManagerRequested()
    onRightClicked: BluetoothService.toggle()

    AetherIcon {
        anchors.centerIn: parent
        width: Metrics.iconSm + 1; height: Metrics.iconSm + 1
        name: "bluetooth"
        color: BluetoothService.enabled ? Colors.accent : Colors.textMuted
    }
}
