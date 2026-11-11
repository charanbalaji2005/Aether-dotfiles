import QtQuick
import "../theme"

// Keyboard focus indicator (Settings → Accessibility → focus rings).
// Shown only for keyboard focus on `target`, drawn just outside it.
Rectangle {
    id: root

    property Item target: parent
    readonly property bool show: target && target.activeFocus && FocusState.ringsEnabled

    x: -3
    y: -3
    width: target ? target.width + 6 : 0
    height: target ? target.height + 6 : 0
    radius: target && target.radius !== undefined ? target.radius + 3 : 6
    color: "transparent"
    border.width: Metrics.focusRing
    border.color: Colors.accent
    visible: show
}
