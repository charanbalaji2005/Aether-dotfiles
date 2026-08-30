pragma Singleton
import Quickshell
import Quickshell.Io
import "../core"

// Uses the dedicated aether-screenshot helper (which wraps grim + slurp and wl-copy)
// to capture screens cleanly without dynamic shell string construction in QML.
Singleton {
    id: root

    property bool available: false

    Process {
        id: checkProcess
        command: ["bash", "-c", "command -v grim >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector {
            onStreamFinished: root.available = this.text.trim() === "yes"
        }
    }

    Process {
        id: captureProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const path = this.text.trim();
                if (path.length > 0) {
                    Logger.info("ScreenshotService", "Saved " + path);
                    EventBus.notificationRequested("Screenshot saved", path, "normal");
                }
            }
        }
    }

    function captureFullScreen() {
        if (!available) { Logger.warn("ScreenshotService", "grim not found on PATH"); return; }
        captureProcess.command = ["aether-screenshot", "full"];
        captureProcess.running = true;
    }

    function captureRegion() {
        if (!available) { Logger.warn("ScreenshotService", "grim not found on PATH"); return; }
        captureProcess.command = ["aether-screenshot", "region"];
        captureProcess.running = true;
    }

    Component.onCompleted: checkProcess.running = true
}
