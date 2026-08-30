import QtQuick
import Quickshell.Services.SystemTray
import "../../theme"

Row {
    id: root
    spacing: Metrics.spaceSm
    height: Metrics.barHeight
    visible: SystemTray.items.count > 0

    Repeater {
        model: SystemTray.items

        delegate: Image {
            required property var modelData
            source: modelData.icon
            width: 16
            height: 16
            anchors.verticalCenter: parent.verticalCenter
            smooth: true

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: modelData.activate()
            }
        }
    }
}
