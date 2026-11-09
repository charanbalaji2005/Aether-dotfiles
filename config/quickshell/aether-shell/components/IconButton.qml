import QtQuick
import "../theme"

// Round icon button with hover/press feedback.
Rectangle {
    id: root

    property string icon: ""
    property int iconSize: Metrics.iconMd
    property color iconColor: active ? Colors.onAccent : Colors.textPrimary
    property bool active: false
    property bool enabledState: true
    readonly property bool hovered: area.containsMouse
    signal clicked()
    signal rightClicked()

    implicitWidth: 32
    implicitHeight: 32
    radius: Metrics.radiusPill
    opacity: enabledState ? 1 : 0.4
    color: active ? Colors.accent
        : area.pressed ? Colors.surfaceActive
        : hovered ? Colors.surfaceHover
        : "transparent"

    Behavior on color { enabled: !Motion.reducedMotion; ColorAnimation { duration: Motion.fast } }

    scale: area.pressed ? 0.92 : 1.0
    Behavior on scale { enabled: !Motion.reducedMotion; NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

    AetherIcon {
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        name: root.icon
        color: root.iconColor
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabledState
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) root.rightClicked();
            else root.clicked();
        }
    }
}
