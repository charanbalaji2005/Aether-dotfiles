import QtQuick
import "../theme"

// Toggle switch. `checked` should be bound to the real state; clicking
// emits toggled(newState) and does NOT assign `checked` itself, so the
// binding is never broken (the source of truth updates, the switch follows).
Rectangle {
    id: root

    property bool checked: false
    signal toggled(bool checked)

    implicitWidth: 40
    implicitHeight: 22
    radius: Metrics.radiusPill
    color: checked ? Colors.accent : Colors.withAlpha(Colors.textMuted, 0.3)

    Behavior on color { enabled: !Motion.reducedMotion; ColorAnimation { duration: Motion.fast } }

    Rectangle {
        width: 18
        height: 18
        radius: 9
        color: "white"
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - 2 : 2

        Behavior on x { enabled: !Motion.reducedMotion; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
