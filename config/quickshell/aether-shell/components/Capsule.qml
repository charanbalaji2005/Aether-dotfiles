import QtQuick
import "../theme"

Rectangle {
    id: root

    property bool interactive: true
    readonly property bool hovered: mouseArea.containsMouse
    signal clicked()

    implicitHeight: Metrics.barHeight - Metrics.spaceSm
    radius: Metrics.radiusPill
    color: (interactive && hovered) ? Colors.withAlpha(Colors.textPrimary, 0.08) : "transparent"

    Behavior on color {
        enabled: !Motion.reducedMotion
        ColorAnimation { duration: Motion.fast }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.interactive
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
