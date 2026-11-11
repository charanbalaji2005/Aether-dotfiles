import QtQuick
import "../theme"
import "../animation"

// Horizontal slider. `value` is meant to be BOUND to the real state (e.g.
// AudioService.volume); dragging emits moved(v) and shows the drag position
// locally, but never overwrites `value` — so the binding survives and the
// slider keeps tracking changes made elsewhere (media keys, other apps).
//
// External changes glide to the new position on a spring; while dragging
// the handle follows the pointer exactly. A value bubble shows during a
// drag. Keyboard: ←/→ step 5 %, PgUp/PgDn 10 %, Home/End.
Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0.5
    property bool showBubble: true
    // Formats the bubble text from a value.
    property var format: function(v) { return Math.round((v - root.from) / Math.max(1e-9, root.to - root.from) * 100) + "%"; }
    signal moved(real value)

    property real _dragValue: 0
    readonly property bool dragging: mouseArea.pressed
    readonly property real shownValue: dragging ? _dragValue : value
    readonly property real ratio: (to > from) ? Math.max(0, Math.min(1, (shownValue - from) / (to - from))) : 0

    SpringValue { id: glide; preset: "snappy"; target: root.ratio }
    // Exact under the finger, sprung otherwise.
    readonly property real shownRatio: dragging ? ratio : glide.value
    onDraggingChanged: if (!dragging) glide.snap(root.ratio)
    Component.onCompleted: glide.snap(root.ratio)

    implicitHeight: 20
    implicitWidth: 140
    activeFocusOnTab: true
    Accessible.role: Accessible.Slider
    Accessible.name: root.format(root.value)

    function _step(delta) {
        const v = Math.max(root.from, Math.min(root.to, root.value + delta * (root.to - root.from)));
        root.moved(v);
    }
    Keys.onLeftPressed: _step(-0.05)
    Keys.onRightPressed: _step(0.05)
    Keys.onDownPressed: _step(-0.05)
    Keys.onUpPressed: _step(0.05)
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_PageUp) { _step(0.1); event.accepted = true; }
        else if (event.key === Qt.Key_PageDown) { _step(-0.1); event.accepted = true; }
        else if (event.key === Qt.Key_Home) { root.moved(root.from); event.accepted = true; }
        else if (event.key === Qt.Key_End) { root.moved(root.to); event.accepted = true; }
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: mouseArea.containsMouse || root.dragging || root.activeFocus ? 6 : 4
        radius: height / 2
        color: Colors.withAlpha(Colors.textMuted, 0.25)
        Behavior on height { enabled: Motion.animate; NumberAnimation { duration: Motion.fast } }

        Rectangle {
            width: track.width * root.shownRatio
            height: parent.height
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Colors.withAlpha(Colors.accent, 0.75) }
                GradientStop { position: 1; color: Colors.accent }
            }
        }
    }

    Rectangle {
        id: handle
        width: root.dragging ? 18 : 14
        height: width
        radius: width / 2
        color: Colors.dark ? Colors.textPrimary : "#FFFFFF"
        border.width: Colors.dark ? 0 : 1
        border.color: Colors.borderStrong
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(root.width - width, track.width * root.shownRatio - width / 2))
        SpringBehavior on width { preset: "bouncy" }

        // Value bubble.
        Rectangle {
            visible: opacity > 0
            opacity: root.dragging && root.showBubble ? 1 : 0
            Behavior on opacity { enabled: Motion.animate; NumberAnimation { duration: Motion.fast } }
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.top
            anchors.bottomMargin: 6
            width: bubbleText.implicitWidth + 12
            height: bubbleText.implicitHeight + 6
            radius: height / 2
            color: Colors.accent
            Text {
                id: bubbleText
                anchors.centerIn: parent
                text: root.format(root.shownValue)
                color: Colors.onAccent
                font.family: Typography.family
                font.pixelSize: Typography.sizeXs
                font.weight: Typography.weightSemibold
            }
        }
    }

    FocusRing { target: root; radius: 6 }

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

        onPressed: function(mouse) { root.forceActiveFocus(); updateFromX(mouse.x); }
        onPositionChanged: function(mouse) { if (pressed) updateFromX(mouse.x) }
        onWheel: function(wheel) {
            const step = (root.to - root.from) * 0.05;
            const v = Math.max(root.from, Math.min(root.to, root.value + (wheel.angleDelta.y > 0 ? step : -step)));
            root.moved(v);
        }
    }
}
