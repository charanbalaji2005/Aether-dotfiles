import QtQuick
import QtQuick.Layouts
import "../theme"

Rectangle {
    id: root

    property string label: ""
    property bool active: false
    signal clicked()

    Layout.fillWidth: true
    implicitHeight: 56
    radius: Metrics.radiusMd
    color: active ? Colors.withAlpha(Colors.accent, 0.22) : Colors.withAlpha(Colors.textMuted, 0.1)
    border.width: Metrics.borderWidth
    border.color: active ? Colors.accent : Colors.border

    Behavior on color { enabled: !Motion.reducedMotion; ColorAnimation { duration: Motion.fast } }

    Text {
        anchors.centerIn: parent
        text: root.label
        color: root.active ? Colors.accent : Colors.textSecondary
        font.family: Typography.family
        font.pixelSize: Typography.sizeSm
        font.weight: Typography.weightMedium
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
