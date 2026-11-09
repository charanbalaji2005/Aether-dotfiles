import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import "../../theme"
import "../../core"
import "../../services"

// Fetches the active window title via `hyprctl -j activewindow` rather than
// undocumented internal QML properties — this is Hyprland's own stable
// public JSON IPC contract, refreshed on every compositor event plus a
// short fallback poll.
Item {
    id: root
    property real maxWidth: 420
    implicitHeight: Config.bar.height
    implicitWidth: Math.min(label.implicitWidth, maxWidth, 420)
    visible: HyprlandService.available && Config.bar.showActiveWindow && maxWidth > 40

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

    // Only focus/title events change the title; ignore the rest of the
    // (very chatty) event stream.
    Connections {
        target: HyprlandService.available ? Hyprland : null
        function onRawEvent(event) {
            const n = event ? event.name : "";
            if (n === "activewindow" || n === "activewindowv2" || n === "windowtitle" || n === "windowtitlev2"
                || n === "closewindow" || n === "workspace" || n === "focusedmon") root.refresh();
        }
    }

    // Safety net only; events do the real work.
    Timer {
        interval: 10000
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
