import QtQuick
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// Now playing (MPRIS). Click: play/pause. Scroll: next/previous track.
Capsule {
    id: root
    visible: MediaService.available && Config.bar.showMedia && Config.bar.style !== "dock"
    implicitWidth: Math.min(row.implicitWidth + Metrics.spaceMd * 2, 240)
    onClicked: MediaService.playPause()

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
            if (wheel.angleDelta.y > 0) MediaService.previous();
            else MediaService.next();
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Metrics.spaceXs

        AetherIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: 12; height: 12
            name: MediaService.playing ? "pause" : "play"
            color: Colors.accent
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: MediaService.artist.length > 0 ? (MediaService.artist + " – " + MediaService.title) : MediaService.title
            color: Colors.textSecondary
            font.family: Typography.family
            font.pixelSize: Typography.sizeSm
            elide: Text.ElideRight
            width: Math.min(implicitWidth, 180)
        }
    }
}
