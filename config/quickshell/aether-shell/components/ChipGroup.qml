import QtQuick
import "../theme"
import "../animation"

// A wrapping set of selectable chips for "pick one of many" settings.
//   ChipGroup { options: [{ value: "fade", label: "Fade" }, …]; current: x; onSelected: v => … }
// Arrow keys move the selection when focused.
Flow {
    id: root

    property var options: []
    property string current: ""
    signal selected(string value)

    spacing: Metrics.spaceXs
    activeFocusOnTab: true
    Keys.onRightPressed: _move(1)
    Keys.onLeftPressed: _move(-1)
    function _move(d) {
        const i = root.options.findIndex(function(o) { return o.value === root.current; });
        const n = root.options.length;
        if (n) root.selected(root.options[((i < 0 ? 0 : i) + d + n) % n].value);
    }

    Repeater {
        model: root.options
        delegate: Rectangle {
            id: chip
            required property var modelData
            readonly property bool on: root.current === modelData.value
            implicitWidth: label.implicitWidth + 22
            implicitHeight: 28
            radius: 14
            color: on ? Colors.accent : (ma.containsMouse ? Colors.surfaceHover : Colors.withAlpha(Colors.textMuted, 0.12))
            border.width: root.activeFocus && on ? 2 : 0
            border.color: Colors.textPrimary
            Behavior on color { enabled: Motion.animate; ColorAnimation { duration: Motion.fast } }
            scale: press.value
            SpringValue { id: press; preset: "snappy"; target: ma.pressed ? 0.93 : 1 }
            Component.onCompleted: press.snap(1)
            Text {
                id: label
                anchors.centerIn: parent
                text: chip.modelData.label
                color: chip.on ? Colors.onAccent : Colors.textSecondary
                font.family: Typography.family
                font.pixelSize: Typography.sizeXs
                font.weight: Typography.weightMedium
            }
            MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selected(chip.modelData.value) }
            Accessible.role: Accessible.RadioButton
            Accessible.name: chip.modelData.label
            Accessible.checked: chip.on
        }
    }
}
