pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// Backlight brightness through `brightnessctl` (works without root via
// systemd-logind). Desktops with no backlight device report unavailable
// and the brightness slider hides itself — external monitors over DDC/CI
// are not controlled (see docs/TROUBLESHOOTING.md).
//
// Brightness keys run brightnessctl directly (keybinds.conf) and then call
// `qs ... ipc call osd brightness`, which refreshes this service.
Singleton {
    id: root

    property bool available: false
    property real value: 0      // 0-1
    property string device: ""

    Process {
        id: readProcess
        // Machine-readable: device,class,current,percent,max
        command: ["brightnessctl", "-m", "--class=backlight", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.trim().split("\n")[0].split(",");
                if (p.length >= 5) {
                    const cur = parseFloat(p[2]), max = parseFloat(p[4]);
                    root.device = p[0];
                    root.available = max > 0;
                    if (max > 0) root.value = cur / max;
                } else {
                    root.available = false;
                }
            }
        }
        onExited: function(code) { if (code !== 0) root.available = false; }
    }

    Process {
        id: writeProcess
        onExited: readProcess.running = true
    }

    Timer {
        id: debounce
        interval: 60
        property real pending: 0
        onTriggered: {
            writeProcess.command = ["brightnessctl", "--class=backlight", "set", Math.round(pending * 100) + "%"];
            writeProcess.running = true;
        }
    }

    function refresh() { readProcess.running = true; }

    // Clamped to 1% so the screen can't be blanked from the slider.
    function set(v) {
        const clamped = Math.max(0.01, Math.min(1, v));
        root.value = clamped;
        debounce.pending = clamped;
        debounce.restart();
    }

    Component.onCompleted: refresh()
}
