import QtQuick
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

Capsule {
    id: root
    visible: MediaService.available && Config.bar.showMedia
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

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: MediaService.playing ? "\u25B8" : "\u23F8"
            color: Colors.accent
            font.pixelSize: Typography.sizeSm
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: MediaService.artist.length > 0 ? (MediaService.artist + " \u2013 " + MediaService.title) : MediaService.title
            color: Colors.textSecondary
            font.family: Typography.family
            font.pixelSize: Typography.sizeSm
            elide: Text.ElideRight
            width: Math.min(implicitWidth, 180)
        }
    }
}
