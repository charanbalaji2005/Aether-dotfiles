import QtQuick
import QtQuick.Layouts
import "../theme"
import "../animation"

// Control-centre tile: icon + title + status line. Clicking the body
// toggles; the optional chevron opens details (e.g. the Wi-Fi network list).
// A tile whose backend is unavailable is shown disabled with the reason —
// it never pretends to work.
Rectangle {
    id: root

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool active: false
    property bool available: true
    property bool busy: false
    property bool expandable: false
    signal toggled()
    signal expand()

    Layout.fillWidth: true
    implicitHeight: 58
    radius: Metrics.radiusLg
    opacity: available ? 1 : 0.45
    color: active ? Colors.accent
        : body.containsMouse ? Colors.surfaceHover
        : Colors.withAlpha(Colors.surface, Colors.dark ? 0.7 : 0.9)
    border.width: active ? 0 : Metrics.borderWidth
    border.color: Colors.withAlpha(Colors.border, 0.7)

    Behavior on color { enabled: !Motion.reducedMotion; ColorAnimation { duration: Motion.normal } }

    scale: press.value
    SpringValue { id: press; preset: "bouncy"; target: body.pressed ? 0.95 : 1.0 }
    Component.onCompleted: press.snap(1.0)

    readonly property color fg: active ? Colors.onAccent : Colors.textPrimary

    MouseArea {
        id: body
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.available
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Metrics.spaceMd
        anchors.rightMargin: root.expandable ? 0 : Metrics.spaceMd
        spacing: Metrics.spaceSm

        Rectangle {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 16
            color: root.active ? Colors.withAlpha(Colors.onAccent, 0.16) : Colors.withAlpha(Colors.textMuted, 0.14)
            AetherIcon {
                anchors.centerIn: parent
                width: Metrics.iconMd; height: Metrics.iconMd
                name: root.icon
                color: root.fg
            }
            Spinner {
                anchors.centerIn: parent
                width: 30; height: 30
                visible: root.busy
                color: root.fg
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                text: root.title
                color: root.fg
                font.family: Typography.family
                font.pixelSize: Typography.sizeSm
                font.weight: Typography.weightSemibold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                visible: text.length > 0
                text: root.subtitle
                color: root.active ? Colors.withAlpha(Colors.onAccent, 0.8) : Colors.textMuted
                font.family: Typography.family
                font.pixelSize: Typography.sizeXs
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        Rectangle {
            visible: root.expandable
            Layout.preferredWidth: 30
            Layout.fillHeight: true
            color: "transparent"
            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 1; height: parent.height * 0.5
                color: root.active ? Colors.withAlpha(Colors.onAccent, 0.25) : Colors.border
            }
            AetherIcon {
                anchors.centerIn: parent
                width: Metrics.iconSm; height: Metrics.iconSm
                name: "chevron-right"
                color: root.fg
            }
            MouseArea {
                anchors.fill: parent
                enabled: root.available
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expand()
            }
        }
    }
}
