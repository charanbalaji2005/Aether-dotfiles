import QtQuick
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// Clicking opens the full Bluetooth manager (shell/bluetooth/BluetoothManager.qml)
// for device list/pairing/connect — this capsule itself is just a status
// indicator and an entry point, not where power gets toggled directly.
Capsule {
    id: root
    visible: BluetoothService.available && Config.bar.showBluetooth
    implicitWidth: row.implicitWidth + Metrics.spaceMd * 2
    onClicked: EventBus.bluetoothManagerRequested()

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Metrics.spaceXs

        Rectangle {
            width: 6
            height: 6
            radius: 3
            anchors.verticalCenter: parent.verticalCenter
            color: BluetoothService.enabled ? Colors.accent : Colors.textMuted
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Bluetooth"
            color: BluetoothService.enabled ? Colors.textPrimary : Colors.textMuted
            font.family: Typography.family
            font.pixelSize: Typography.sizeSm
        }
    }
}
