import QtQuick
import "../theme"

// Staggered entrance for one item of a list or grid.
//
//   delegate: Reveal { index: model.index; shown: panel.open; ... content ... }
//
// The content rises `distance` px and fades in, delayed by
// Motion.staggerDelay(index) so a list cascades instead of popping in as a
// block. Driven by a SpringValue, so closing mid-cascade reverses smoothly.
// Under reduced motion everything is instantly visible.
Item {
    id: root

    property int index: 0
    property bool shown: true
    property real distance: Motion.travel
    property real fromScale: 0.97
    property string preset: "smooth"
    default property alias content: holder.data

    implicitWidth: holder.childrenRect.width
    implicitHeight: holder.childrenRect.height

    SpringValue {
        id: progress
        preset: root.preset
        target: 0
    }

    Timer {
        id: delay
        interval: Motion.staggerDelay(root.index)
        onTriggered: progress.target = 1
    }

    function _apply() {
        if (root.shown) {
            if (delay.interval <= 0 || !Motion.animate) { delay.stop(); progress.target = 1; }
            else delay.restart();
        } else {
            delay.stop();
            progress.target = 0;
        }
    }
    onShownChanged: _apply()
    Component.onCompleted: {
        if (!Motion.animate) progress.snap(root.shown ? 1 : 0);
        _apply();
    }

    Item {
        id: holder
        width: root.width
        height: root.height
        opacity: Math.max(0, Math.min(1, progress.value))
        y: (1 - progress.value) * root.distance
        scale: root.fromScale + (1 - root.fromScale) * progress.value
        transformOrigin: Item.Top
    }
}
