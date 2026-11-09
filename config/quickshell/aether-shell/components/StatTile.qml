import QtQuick
import QtQuick.Layouts
import "../theme"

// Dashboard metric tile: icon, label, big value, secondary detail, and an
// optional history graph. When `available` is false it says so (with the
// reason) instead of showing a misleading number.
Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property string value: ""
    property string detail: ""
    property var history: []
    property real ratio: -1          // 0-1 colours the value; -1 = neutral
    property bool available: true
    property string unavailableReason: "Not available on this system"
    property color graphColor: ratio >= 0 ? Colors.load(ratio) : Colors.accent

    radius: Metrics.radiusMd
    color: Colors.withAlpha(Colors.surface, Colors.dark ? 0.55 : 0.75)
    border.width: Metrics.borderWidth
    border.color: Colors.withAlpha(Colors.border, 0.8)
    implicitHeight: layout.implicitHeight + Metrics.spaceMd * 2

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Metrics.spaceMd
        spacing: Metrics.spaceXs

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            AetherIcon {
                visible: root.icon.length > 0
                width: Metrics.iconMd; height: Metrics.iconMd
                name: root.icon
                color: Colors.textMuted
            }
            Text {
                text: root.label
                color: Colors.textSecondary
                font.family: Typography.family
                font.pixelSize: Typography.sizeSm
                font.weight: Typography.weightMedium
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Text {
                visible: root.available && root.detail.length > 0
                text: root.detail
                color: Colors.textMuted
                font.family: Typography.family
                font.pixelSize: Typography.sizeXs
            }
        }

        Text {
            text: root.available ? root.value : "Unavailable"
            color: !root.available ? Colors.textMuted : (root.ratio >= 0 ? Colors.load(root.ratio) : Colors.textPrimary)
            font.family: Typography.family
            font.pixelSize: root.available ? Typography.sizeXl : Typography.sizeLg
            font.weight: Typography.weightSemibold
            Behavior on color { enabled: !Motion.reducedMotion; ColorAnimation { duration: Motion.normal } }
        }

        Text {
            visible: !root.available
            text: root.unavailableReason
            color: Colors.textMuted
            font.family: Typography.family
            font.pixelSize: Typography.sizeXs
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Sparkline {
            visible: root.available && root.history.length > 1
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            values: root.history
            lineColor: root.graphColor
        }
    }
}
