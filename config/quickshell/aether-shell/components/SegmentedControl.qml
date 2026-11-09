import QtQuick
import "../theme"

// Pill-shaped single-choice selector with a sliding highlight.
// options: [{ value: "dark", label: "Dark" }, ...]
Rectangle {
    id: root

    property var options: []
    property string current: ""
    signal selected(string value)

    readonly property int _index: {
        for (let i = 0; i < options.length; i++) if (options[i].value === current) return i;
        return -1;
    }

    implicitHeight: 30
    implicitWidth: row.implicitWidth + 6
    radius: Metrics.radiusPill
    color: Colors.withAlpha(Colors.textMuted, 0.14)

    Rectangle {
        id: thumb
        visible: root._index >= 0 && repeater.count > 0
        y: 3
        height: parent.height - 6
        radius: Metrics.radiusPill
        color: Colors.accent
        // Depends on repeater.count so it re-evaluates once delegates exist
        // (itemAt() alone isn't a notifying dependency).
        readonly property Item target: (root._index >= 0 && repeater.count > root._index) ? repeater.itemAt(root._index) : null
        x: target ? row.x + target.x : 3
        width: target ? target.width : 0
        Behavior on x { enabled: !Motion.reducedMotion; NumberAnimation { duration: Motion.normal; easing.type: Motion.easeStandard } }
        Behavior on width { enabled: !Motion.reducedMotion; NumberAnimation { duration: Motion.normal; easing.type: Motion.easeStandard } }
    }

    Row {
        id: row
        x: 3
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
            id: repeater
            model: root.options
            delegate: Item {
                id: opt
                required property var modelData
                required property int index
                width: label.implicitWidth + Metrics.spaceLg
                height: root.height - 6
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: opt.modelData.label
                    color: opt.index === root._index ? Colors.onAccent : Colors.textSecondary
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeXs
                    font.weight: Typography.weightMedium
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selected(opt.modelData.value)
                }
            }
        }
    }
}
