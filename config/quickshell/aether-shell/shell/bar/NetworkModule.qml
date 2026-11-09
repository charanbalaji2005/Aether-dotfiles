import QtQuick
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// Connection status: Wi-Fi signal level / ethernet / offline. Click opens
// the control centre (Wi-Fi list).
Capsule {
    id: root
    visible: NetworkService.available && Config.bar.showNetwork
    implicitWidth: row.implicitWidth + Metrics.spaceMd * 2
    onClicked: EventBus.controlCenterRequested()

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Metrics.spaceXs

        AetherIcon {
            width: 15
            height: 15
            anchors.verticalCenter: parent.verticalCenter
            name: {
                if (!NetworkService.connected) return "wifi-off";
                if (NetworkService.connectionType === "ethernet") return "ethernet";
                return "wifi";
            }
            level: NetworkService.signalLevel
            color: NetworkService.connected ? Colors.textPrimary : Colors.textMuted
        }

        Text {
            visible: NetworkService.connectionType === "wifi" && NetworkService.ssid.length > 0 && Config.bar.style !== "dock"
            anchors.verticalCenter: parent.verticalCenter
            text: NetworkService.ssid
            color: Colors.textSecondary
            font.family: Typography.family
            font.pixelSize: Typography.sizeSm
            elide: Text.ElideRight
            width: Math.min(implicitWidth, 110)
        }
    }
}
