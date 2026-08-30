import QtQuick
import "../../theme"
import "../../services"

Row {
    id: root
    spacing: Metrics.spaceXs
    height: Metrics.barHeight
    visible: HyprlandService.available

    Repeater {
        model: HyprlandService.workspaces

        delegate: Rectangle {
            id: dot
            required property var modelData
            readonly property bool focused: HyprlandService.focusedWorkspace
                && HyprlandService.focusedWorkspace.id === modelData.id

            width: focused ? 22 : 10
            height: 10
            radius: Metrics.radiusPill
            color: focused ? Colors.accent : Colors.withAlpha(Colors.textMuted, 0.5)
            anchors.verticalCenter: parent.verticalCenter

            Behavior on width {
                enabled: !Motion.reducedMotion
                NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
            }
            Behavior on color {
                enabled: !Motion.reducedMotion
                ColorAnimation { duration: Motion.fast }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: HyprlandService.switchToWorkspace(dot.modelData.id)
            }
        }
    }
}
