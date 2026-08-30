import QtQuick
import "../../theme"
import "../../components"

Capsule {
    id: root
    interactive: false
    implicitWidth: label.implicitWidth + Metrics.spaceMd * 2

    property string timeText: Qt.formatDateTime(new Date(), "hh:mm")
    property string dateText: Qt.formatDateTime(new Date(), "ddd d MMM")

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.timeText = Qt.formatDateTime(new Date(), "hh:mm");
            root.dateText = Qt.formatDateTime(new Date(), "ddd d MMM");
        }
    }

    Row {
        id: label
        anchors.centerIn: parent
        spacing: Metrics.spaceSm

        Text {
            text: root.timeText
            color: Colors.textPrimary
            font.family: Typography.family
            font.pixelSize: Typography.sizeMd
            font.weight: Typography.weightSemibold
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.dateText
            color: Colors.textMuted
            font.family: Typography.family
            font.pixelSize: Typography.sizeSm
        }
    }
}
