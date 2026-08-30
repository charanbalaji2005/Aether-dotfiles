import QtQuick
import "../theme"

Rectangle {
    id: root

    property color swatchColor: Colors.accent
    property bool selected: false
    signal clicked()

    width: 28
    height: 28
    radius: 14
    color: swatchColor
    border.width: selected ? 3 : 0
    border.color: Colors.textPrimary

    Behavior on border.width { enabled: !Motion.reducedMotion; NumberAnimation { duration: Motion.fast } }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
