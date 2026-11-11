import QtQuick
import "../theme"
import "../animation"

// The AetherOS "liquid" toggle. `checked` should be bound to the real
// state; clicking emits toggled(newState) and never assigns `checked`
// itself, so the binding is never broken (the source of truth updates, the
// switch follows).
//
// The knob rides a spring; while moving it stretches along the track in
// proportion to its speed (like a droplet) and settles round. Keyboard:
// Space/Enter toggle when focused.
Rectangle {
    id: root

    property bool checked: false
    property bool enabled: true
    signal toggled(bool checked)

    implicitWidth: 42
    implicitHeight: 24
    radius: Metrics.radiusPill
    opacity: enabled ? 1 : 0.45
    color: Colors.mix(Colors.withAlpha(Colors.textMuted, 0.3), Colors.accent, Math.max(0, Math.min(1, pos.value)))
    activeFocusOnTab: true

    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: root.checked
    Keys.onSpacePressed: if (root.enabled) root.toggled(!root.checked)
    Keys.onReturnPressed: if (root.enabled) root.toggled(!root.checked)

    SpringValue { id: pos; preset: "snappy"; target: root.checked ? 1 : 0 }
    Component.onCompleted: pos.snap(root.checked ? 1 : 0)

    readonly property real knob: height - 4
    // Stretch with speed: up to 45 % longer at full tilt.
    readonly property real stretch: Math.min(knob * 0.45, Math.abs(pos.velocity) * knob * 0.035)

    Rectangle {
        width: root.knob + root.stretch
        height: root.knob - root.stretch * 0.25
        radius: height / 2
        color: "white"
        anchors.verticalCenter: parent.verticalCenter
        // Lead with the edge in the direction of travel.
        x: 2 + (root.width - root.knob - 4) * pos.value - (pos.velocity > 0 ? root.stretch : 0)
        border.width: Colors.dark ? 0 : 1
        border.color: Colors.withAlpha(Colors.borderStrong, 0.6)
    }

    FocusRing { target: root }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: { root.forceActiveFocus(); root.toggled(!root.checked); }
    }
}
