import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"
import "../../core"
import "../../services"

// Toggle from Hyprland with:
//   bind = SUPER, Escape, exec, qs -c aether-shell ipc call powermenu toggle
Scope {
    id: root

    PanelWindow {
        id: window
        visible: false
        screen: ShellState.activeScreen ? ShellState.activeScreen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
        WlrLayershell.namespace: "aether-powermenu"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        property string armed: ""

        function open() { armed = ""; visible = true; }
        function close() { visible = false; }
        function toggleVisible() { if (visible) close(); else open(); }

        MouseArea {
            anchors.fill: parent
            onClicked: window.close()
        }

        Rectangle {
            anchors.fill: parent
            color: Colors.withAlpha("#000000", 0.4)
        }

        Row {
            anchors.centerIn: parent
            spacing: Metrics.spaceLg

            Repeater {
                model: [
                    { id: "lock", label: "Lock", destructive: false },
                    { id: "logout", label: "Log Out", destructive: true },
                    { id: "suspend", label: "Suspend", destructive: false },
                    { id: "reboot", label: "Reboot", destructive: true },
                    { id: "shutdown", label: "Shut Down", destructive: true }
                ]

                delegate: Rectangle {
                    id: card
                    required property var modelData

                    width: 130
                    height: 130
                    radius: Metrics.radiusLg
                    color: window.armed === card.modelData.id
                        ? Colors.withAlpha(Colors.danger, 0.3)
                        : Colors.withAlpha(Colors.glass, 0.85)
                    border.width: Metrics.borderWidth
                    border.color: window.armed === card.modelData.id ? Colors.danger : Colors.borderStrong

                    Behavior on color { enabled: !Motion.reducedMotion; ColorAnimation { duration: Motion.fast } }

                    function _runAction() {
                        switch (card.modelData.id) {
                        case "lock": SessionService.lock(); break;
                        case "logout": SessionService.logout(); break;
                        case "suspend": SessionService.suspend(); break;
                        case "reboot": SessionService.reboot(); break;
                        case "shutdown": SessionService.shutdown(); break;
                        }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Metrics.spaceXs

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: card.modelData.label
                            color: Colors.textPrimary
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeMd
                            font.weight: Typography.weightMedium
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            visible: window.armed === card.modelData.id
                            text: "Click again to confirm"
                            color: Colors.danger
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeXs
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!card.modelData.destructive) {
                                card._runAction();
                                window.close();
                                return;
                            }
                            if (window.armed === card.modelData.id) {
                                card._runAction();
                                window.close();
                            } else {
                                window.armed = card.modelData.id;
                                armTimer.restart();
                            }
                        }
                    }
                }
            }
        }

        Timer {
            id: armTimer
            interval: 3000
            onTriggered: window.armed = ""
        }
    }

    Connections {
        target: EventBus
        function onClosePopups(except) { if (except !== "aether-powermenu" && window.visible) window.close(); }
        function onPowerMenuRequested() { EventBus.closePopups("aether-powermenu"); window.open(); }
    }

    IpcHandler {
        target: "powermenu"
        function toggle(): void { window.toggleVisible(); }
        function show(): void { window.open(); }
        function hide(): void { window.close(); }
    }
}
