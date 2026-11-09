import QtQuick
import "../theme"
import "../core"

// Rounded, hoverable container used by every bar module.
Rectangle {
    id: root

    property bool interactive: true
    property bool highlighted: false
    readonly property bool hovered: mouseArea.containsMouse
    signal clicked()
    signal rightClicked()
    signal middleClicked()

    implicitHeight: Math.max(22, Config.bar.height - 12)
    radius: Metrics.radiusPill
    color: highlighted ? Colors.accentSoft
        : (interactive && mouseArea.pressed) ? Colors.withAlpha(Colors.textPrimary, 0.14)
        : (interactive && hovered) ? Colors.withAlpha(Colors.textPrimary, 0.08)
        : "transparent"

    Behavior on color {
        enabled: !Motion.reducedMotion
        ColorAnimation { duration: Motion.fast }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.interactive
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) root.rightClicked();
            else if (mouse.button === Qt.MiddleButton) root.middleClicked();
            else root.clicked();
        }
    }
}
