import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../services"
import "../../components"

// Toggle from Hyprland with:
//   bind = SUPER, D, exec, qs -c aether-shell ipc call launcher toggle
Scope {
    id: root

    function _launchSelected() {
        const app = window.results[window.selectedIndex];
        if (app) {
            ApplicationService.launch(app);
            window.close();
        }
    }

    PanelWindow {
        id: window
        visible: false
        focusable: true
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        property var results: []
        property int selectedIndex: 0

        function open() {
            visible = true;
            searchField.text = "";
            results = ApplicationService.search("");
            selectedIndex = 0;
            searchField.forceActiveFocus();
        }
        function close() {
            visible = false;
        }
        function toggleVisible() {
            if (visible) close(); else open();
        }

        MouseArea {
            anchors.fill: parent
            onClicked: window.close()
        }

        Rectangle {
            anchors.fill: parent
            color: Colors.withAlpha("#000000", 0.35)
        }

        Rectangle {
            id: card
            width: Math.min(520, parent.width - 80)
            height: Math.min(440, parent.height - 160)
            anchors.centerIn: parent
            radius: Metrics.radiusLg
            color: Colors.withAlpha(Colors.glass, 0.94)
            border.width: Metrics.borderWidth
            border.color: Colors.borderStrong

            MouseArea {
                // swallow clicks on the card so the backdrop MouseArea
                // behind it doesn't treat them as "click outside to close"
                anchors.fill: parent
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Metrics.spaceLg
                spacing: Metrics.spaceMd

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: searchField.implicitHeight + Metrics.spaceSm

                    TextInput {
                        id: searchField
                        anchors.fill: parent
                        color: Colors.textPrimary
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeLg
                        clip: true
                        cursorVisible: activeFocus
                        selectionColor: Colors.accent

                        Keys.onEscapePressed: window.close()
                        Keys.onDownPressed: window.selectedIndex = Math.min(window.selectedIndex + 1, window.results.length - 1)
                        Keys.onUpPressed: window.selectedIndex = Math.max(window.selectedIndex - 1, 0)
                        Keys.onReturnPressed: root._launchSelected()
                        Keys.onEnterPressed: root._launchSelected()

                        onTextChanged: {
                            window.results = ApplicationService.search(text);
                            window.selectedIndex = 0;
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search applications…"
                            color: Colors.textMuted
                            font: searchField.font
                            visible: searchField.text.length === 0
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: Metrics.borderWidth
                    color: Colors.border
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: window.results
                    currentIndex: window.selectedIndex

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index

                        width: list.width
                        height: 52
                        radius: Metrics.radiusSm
                        color: index === window.selectedIndex ? Colors.withAlpha(Colors.accent, 0.18) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Metrics.spaceSm
                            spacing: Metrics.spaceMd

                            AppIcon {
                                iconName: row.modelData.icon
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                            }

                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true

                                Text {
                                    text: row.modelData.name
                                    color: Colors.textPrimary
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeMd
                                    font.weight: Typography.weightMedium
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: row.modelData.genericName
                                    visible: text.length > 0
                                    color: Colors.textMuted
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeXs
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: window.selectedIndex = row.index
                            onClicked: root._launchSelected()
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        text: "No applications found"
                        color: Colors.textMuted
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeSm
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { window.toggleVisible(); }
        function show(): void { window.open(); }
        function hide(): void { window.close(); }
    }
}
