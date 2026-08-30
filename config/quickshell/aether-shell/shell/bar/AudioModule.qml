import QtQuick
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

Capsule {
    id: root
    visible: AudioService.available && Config.bar.showAudio
    implicitWidth: row.implicitWidth + Metrics.spaceMd * 2
    onClicked: AudioService.toggleMute()

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
            AudioService.adjustVolume(wheel.angleDelta.y > 0 ? 0.05 : -0.05);
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Metrics.spaceXs

        AetherIcon {
            width: 15
            height: 15
            anchors.verticalCenter: parent.verticalCenter
            name: AudioService.muted ? "volume-mute" : (AudioService.volume > 0.5 ? "volume-high" : "volume-low")
            color: AudioService.muted ? Colors.textMuted : Colors.textPrimary
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(AudioService.volume * 100) + "%"
            color: Colors.textSecondary
            font.family: Typography.family
            font.pixelSize: Typography.sizeSm
        }
    }
}
