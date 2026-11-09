import QtQuick
import QtQuick.Layouts
import "../theme"

// Label + optional description on the left, a control on the right.
//   SettingRow { label: "Reduced motion"; description: "..."; Switch { ... } }
RowLayout {
    id: root

    property string label: ""
    property string description: ""
    default property alias control: slot.data

    Layout.fillWidth: true
    spacing: Metrics.spaceMd

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 1
        Text {
            text: root.label
            color: Colors.textPrimary
            font.family: Typography.family
            font.pixelSize: Typography.sizeMd
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
        Text {
            visible: root.description.length > 0
            text: root.description
            color: Colors.textMuted
            font.family: Typography.family
            font.pixelSize: Typography.sizeXs
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    Item {
        id: slot
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }
}
