import QtQuick
import "../theme"
import "../animation"

// An interactive card: lifts towards the pointer on hover (spring), dips
// when pressed, can show a selection glow, and reveals with a stagger when
// `index` is set inside a list.
//
//   MotionCard { selected: current; onClicked: ...; Text { ... } }
Item {
    id: root

    property bool selected: false
    property bool interactive: true
    property int index: -1
    property bool shown: true
    property real radius: Metrics.radiusLg
    property color fill: Colors.withAlpha(Colors.surface, Colors.dark ? 0.72 : 0.92)
    property color hoverFill: Colors.surfaceHover
    default property alias content: inner.data
    readonly property bool hovered: area.containsMouse
    signal clicked(var mouse)
    signal rightClicked(var mouse)
    signal doubleClicked()

    implicitWidth: inner.childrenRect.width
    implicitHeight: inner.childrenRect.height
    activeFocusOnTab: interactive
    Keys.onReturnPressed: root.clicked(null)
    Keys.onSpacePressed: root.clicked(null)

    SpringValue { id: lift; preset: "snappy"; target: !root.interactive ? 0 : area.pressed ? -0.6 : (root.hovered || root.activeFocus) ? 1 : 0 }
    SpringValue { id: appear; preset: "smooth"; target: 0 }
    Timer { id: delay; interval: Motion.staggerDelay(Math.max(0, root.index)); onTriggered: appear.target = root.shown ? 1 : 0 }
    onShownChanged: delay.restart()
    Component.onCompleted: { if (root.index < 0 || !Motion.animate) appear.snap(root.shown ? 1 : 0); else delay.start(); }

    opacity: appear.value
    transform: Translate { y: (1 - appear.value) * Motion.travel - lift.value * 2 }
    scale: 1 + 0.015 * lift.value

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: root.radius
        color: root.hovered && root.interactive ? root.hoverFill : root.fill
        border.width: root.selected ? 1.5 : Metrics.borderWidth
        border.color: root.selected ? Colors.accent : Colors.withAlpha(Colors.border, 0.7)
        Behavior on color { enabled: Motion.animate; ColorAnimation { duration: Motion.fast } }
    }

    Item { id: inner; anchors.fill: parent }

    FocusRing { target: root; radius: root.radius + 3 }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) { if (mouse.button === Qt.RightButton) root.rightClicked(mouse); else root.clicked(mouse); }
        onDoubleClicked: root.doubleClicked()
    }
}
