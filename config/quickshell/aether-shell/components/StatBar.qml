import QtQuick
import QtQuick.Layouts
import "../theme"

ColumnLayout {
    id: root

    property string label: ""
    property real value: 0 // 0-1
    property string detail: ""

    spacing: 4

    RowLayout {
        Layout.fillWidth: true

        Text {
            text: root.label
            color: Colors.textSecondary
            font.family: Typography.family
            font.pixelSize: Typography.sizeSm
            Layout.fillWidth: true
        }
        Text {
            text: root.detail
            color: Colors.textMuted
            font.family: Typography.family
            font.pixelSize: Typography.sizeXs
        }
    }

    Rectangle {
        Layout.fillWidth: true
        height: 6
        radius: 3
        color: Colors.withAlpha(Colors.textMuted, 0.2)

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.value))
            height: parent.height
            radius: 3
            color: root.value > 0.85 ? Colors.danger : Colors.accent

            Behavior on width { enabled: !Motion.reducedMotion; NumberAnimation { duration: Motion.normal } }
        }
    }
}
