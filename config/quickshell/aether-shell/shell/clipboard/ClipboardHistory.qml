import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../services"

// Toggle from Hyprland with:
//   bind = SUPER, V, exec, qs -c aether-shell ipc call clipboard toggle
Scope {
    id: root

    PanelWindow {
        id: window
        visible: false
        focusable: true
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        property var filtered: []

        function open() {
            ClipboardService.refresh();
            filterField.text = "";
            filtered = ClipboardService.entries;
            visible = true;
            filterField.forceActiveFocus();
        }
        function close() { visible = false; }
        function toggleVisible() { if (visible) close(); else open(); }

        function _applyFilter(query) {
            if (!query || query.length === 0) {
                filtered = ClipboardService.entries;
                return;
            }
            const q = query.toLowerCase();
            filtered = ClipboardService.entries.filter(function(e) {
                return e.preview.toLowerCase().indexOf(q) >= 0;
            });
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
            width: Math.min(480, parent.width - 80)
            height: Math.min(480, parent.height - 160)
            anchors.centerIn: parent
            radius: Metrics.radiusLg
            color: Colors.withAlpha(Colors.glass, 0.94)
            border.width: Metrics.borderWidth
            border.color: Colors.borderStrong

            MouseArea {
                anchors.fill: parent // swallow clicks so the backdrop doesn't close on interaction
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Metrics.spaceLg
                spacing: Metrics.spaceMd

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceSm

                    Text {
                        text: "Clipboard"
                        color: Colors.textPrimary
                        font.family: Typography.family
                        font.weight: Typography.weightSemibold
                        font.pixelSize: Typography.sizeLg
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "Clear all"
                        color: Colors.danger
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeSm

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                ClipboardService.wipe();
                                window.filtered = [];
                            }
                        }
                    }
                }

                TextInput {
                    id: filterField
                    Layout.fillWidth: true
                    color: Colors.textPrimary
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeMd
                    clip: true
                    cursorVisible: activeFocus
                    selectionColor: Colors.accent

                    Keys.onEscapePressed: window.close()
                    onTextChanged: window._applyFilter(text)

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Filter history\u2026"
                        color: Colors.textMuted
                        font: filterField.font
                        visible: filterField.text.length === 0
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
                    model: window.filtered

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        width: list.width
                        height: 44
                        radius: Metrics.radiusSm
                        color: hoverArea.containsMouse ? Colors.withAlpha(Colors.accent, 0.14) : "transparent"

                        Text {
                            anchors.fill: parent
                            anchors.margins: Metrics.spaceSm
                            verticalAlignment: Text.AlignVCenter
                            text: row.modelData.preview
                            color: Colors.textSecondary
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeSm
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: hoverArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                ClipboardService.copyEntry(row.modelData);
                                window.close();
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        text: ClipboardService.available ? "Clipboard history is empty" : "cliphist not found on PATH"
                        color: Colors.textMuted
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeSm
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { window.toggleVisible(); }
        function show(): void { window.open(); }
        function hide(): void { window.close(); }
    }
}
