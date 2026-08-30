import QtQuick
import "../theme"

Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0.5
    signal moved(real value)

    implicitHeight: 20

    readonly property real ratio: (to > from) ? (value - from) / (to - from) : 0

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: 2
        color: Colors.withAlpha(Colors.textMuted, 0.25)

        Rectangle {
            width: track.width * root.ratio
            height: parent.height
            radius: 2
            color: Colors.accent
        }
    }

    Rectangle {
        id: handle
        width: 14
        height: 14
        radius: 7
        color: Colors.textPrimary
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(root.width - width, track.width * root.ratio - width / 2))
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        anchors.margins: -6
        cursorShape: Qt.PointingHandCursor

        readonly property int marginPx: 6

        function updateFromX(mx) {
            const adjusted = mx - marginPx; // undo the expanded hit area offset
            const clamped = Math.max(0, Math.min(root.width, adjusted));
            const newRatio = root.width > 0 ? clamped / root.width : 0;
            const newValue = root.from + newRatio * (root.to - root.from);
            root.value = newValue;
            root.moved(newValue);
        }

        onPressed: function(mouse) { updateFromX(mouse.x) }
        onPositionChanged: function(mouse) { if (pressed) updateFromX(mouse.x) }
    }
}
