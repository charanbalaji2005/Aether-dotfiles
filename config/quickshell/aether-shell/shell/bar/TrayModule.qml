import QtQuick
import Quickshell.Services.SystemTray
import "../../theme"
import "../../core"

// StatusNotifierItem system tray. Left-click activates the item; middle-
// click sends a secondary activation. (Right-click menus need a popup
// anchor that isn't wired yet — see PROGRESS.md; the item's own
// activate() usually opens its window, which carries the same actions.)
Row {
    id: root
    spacing: Metrics.spaceSm
    visible: Config.bar.showTray && SystemTray.items.values && SystemTray.items.values.length > 0
    leftPadding: Metrics.spaceXs
    rightPadding: Metrics.spaceXs

    Repeater {
        model: SystemTray.items

        delegate: Item {
            id: trayItem
            required property var modelData
            width: 18
            height: 18
            anchors.verticalCenter: parent.verticalCenter

            Image {
                anchors.fill: parent
                source: trayItem.modelData.icon
                sourceSize.width: 36
                sourceSize.height: 36
                smooth: true
                asynchronous: true
                opacity: area.containsMouse ? 1.0 : 0.85
                scale: area.pressed ? 0.88 : (area.containsMouse ? 1.08 : 1.0)
                Behavior on scale { enabled: !Motion.reducedMotion; NumberAnimation { duration: Motion.fast } }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                    if (mouse.button === Qt.MiddleButton && typeof trayItem.modelData.secondaryActivate === "function")
                        trayItem.modelData.secondaryActivate();
                    else
                        trayItem.modelData.activate();
                }
            }
        }
    }
}
