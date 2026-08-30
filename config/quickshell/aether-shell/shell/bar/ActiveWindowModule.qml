import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import "../../theme"
import "../../services"

// Fetches the active window title via `hyprctl -j activewindow` rather than
// undocumented internal QML properties — this is Hyprland's own stable
// public JSON IPC contract, refreshed on every compositor event plus a
// short fallback poll.
Item {
    id: root
    implicitHeight: Metrics.barHeight
    implicitWidth: Math.min(label.implicitWidth, 420)
    visible: HyprlandService.available

    property string windowTitle: "Desktop"

    Process {
        id: activeWindowProcess
        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text);
                    root.windowTitle = (data && data.title) ? data.title : "Desktop";
                } catch (e) {
                    root.windowTitle = "Desktop";
                }
            }
        }
    }

    function refresh() {
        if (HyprlandService.available) activeWindowProcess.running = true;
    }

    Connections {
        target: HyprlandService.available ? Hyprland : null
        function onRawEvent(event) { root.refresh(); }
    }

    Timer {
        interval: 2000
        running: HyprlandService.available
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        text: root.windowTitle
        color: Colors.textSecondary
        font.family: Typography.family
        font.pixelSize: Typography.sizeSm
        elide: Text.ElideRight
    }
}
