import QtQuick
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// Microphone status. Muted shows a red crossed mic so it's obvious at a
// glance; click toggles mute, scroll adjusts input gain.
Capsule {
    id: root
    visible: AudioService.inputAvailable && Config.bar.showMicrophone
    implicitWidth: implicitHeight
    highlighted: AudioService.inputMuted
    onClicked: AudioService.toggleInputMute()

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
            AudioService.setInputVolume(AudioService.inputVolume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05));
        }
    }

    AetherIcon {
        anchors.centerIn: parent
        width: Metrics.iconSm + 1; height: Metrics.iconSm + 1
        name: AudioService.inputMuted ? "mic-off" : "mic"
        color: AudioService.inputMuted ? Colors.danger : Colors.textPrimary
    }
}
