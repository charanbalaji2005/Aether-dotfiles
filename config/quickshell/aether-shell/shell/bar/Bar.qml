import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme"
import "../../core"

Scope {
    id: root

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: panel
                required property var modelData
                screen: modelData

                anchors {
                    top: Config.bar.position !== "bottom"
                    bottom: Config.bar.position === "bottom"
                    left: true
                    right: true
                }

                implicitHeight: Config.bar.height
                exclusiveZone: Config.bar.height
                color: "transparent"

                Rectangle {
                    anchors.fill: parent
                    color: Colors.withAlpha(Colors.bg0, Config.appearance.barOpacity)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Metrics.spaceMd
                    anchors.rightMargin: Metrics.spaceMd
                    spacing: Metrics.spaceLg

                    WorkspacesModule {
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ActiveWindowModule {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        spacing: Metrics.spaceSm
                        Layout.alignment: Qt.AlignVCenter

                        TrayModule {}
                        MediaModule {}
                        BluetoothModule {}
                        NetworkModule {}
                        AudioModule {}
                        BatteryModule {}
                        ClockModule {}
                    }
                }
            }
        }
    }
}
