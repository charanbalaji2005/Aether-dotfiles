import QtQuick
import "../theme"

// Horizontal slider. `value` is meant to be BOUND to the real state (e.g.
// AudioService.volume); dragging emits moved(v) and shows the drag position
// locally, but never overwrites `value` — so the binding survives and the
// slider keeps tracking changes made elsewhere (media keys, other apps).
Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0.5
    signal moved(real value)

    property real _dragValue: 0
    readonly property bool dragging: mouseArea.pressed
    readonly property real shownValue: dragging ? _dragValue : value
    readonly property real ratio: (to > from) ? Math.max(0, Math.min(1, (shownValue - from) / (to - from))) : 0

    implicitHeight: 20
    implicitWidth: 140

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: mouseArea.containsMouse || root.dragging ? 6 : 4
        radius: height / 2
        color: Colors.withAlpha(Colors.textMuted, 0.25)
        Behavior on height { enabled: !Motion.reducedMotion; NumberAnimation { duration: Motion.fast } }

        Rectangle {
            width: track.width * root.ratio
            height: parent.height
            radius: parent.radius
            color: Colors.accent
        }
    }

    Rectangle {
        id: handle
        width: root.dragging ? 16 : 14
        height: width
        radius: width / 2
        color: Colors.dark ? Colors.textPrimary : "#FFFFFF"
        border.width: Colors.dark ? 0 : 1
        border.color: Colors.borderStrong
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(root.width - width, track.width * root.ratio - width / 2))
        Behavior on width { enabled: !Motion.reducedMotion; NumberAnimation { duration: Motion.fast } }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        readonly property int marginPx: 6

        function updateFromX(mx) {
            const adjusted = mx - marginPx; // undo the expanded hit area offset
            const clamped = Math.max(0, Math.min(root.width, adjusted));
            const newRatio = root.width > 0 ? clamped / root.width : 0;
            const newValue = root.from + newRatio * (root.to - root.from);
            root._dragValue = newValue;
            root.moved(newValue);
        }

        onPressed: function(mouse) { updateFromX(mouse.x) }
        onPositionChanged: function(mouse) { if (pressed) updateFromX(mouse.x) }
        onWheel: function(wheel) {
            const step = (root.to - root.from) * 0.05;
            const v = Math.max(root.from, Math.min(root.to, root.value + (wheel.angleDelta.y > 0 ? step : -step)));
            root.moved(v);
        }
    }
}
