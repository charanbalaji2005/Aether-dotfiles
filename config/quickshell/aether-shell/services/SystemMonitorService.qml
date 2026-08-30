pragma Singleton
import Quickshell
import Quickshell.Io
import "../core"

// Reads /proc/stat, /proc/meminfo, and `df` directly rather than depending
// on any QML system-monitor module (none exists in Quickshell) — these are
// stable, well-documented Linux interfaces, not something to reimplement
// via a library.
Singleton {
    id: root

    property real cpuUsage: 0   // 0-1
    property real memUsage: 0   // 0-1
    property real memUsedGb: 0
    property real memTotalGb: 0
    property real diskUsage: 0  // 0-1
    property real diskUsedGb: 0
    property real diskTotalGb: 0

    property var _lastCpu: null // {total, idle}

    Process {
        id: statProcess
        command: ["cat", "/proc/stat"]
        stdout: StdioCollector {
            onStreamFinished: root._parseCpu(this.text)
        }
    }

    Process {
        id: memProcess
        command: ["cat", "/proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: root._parseMem(this.text)
        }
    }

    Process {
        id: diskProcess
        command: ["df", "-B1", "/"]
        stdout: StdioCollector {
            onStreamFinished: root._parseDisk(this.text)
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    function refresh() {
        statProcess.running = true;
        memProcess.running = true;
        diskProcess.running = true;
    }

    function _parseCpu(text) {
        const line = text.split("\n")[0]; // "cpu  user nice system idle iowait irq softirq ..."
        const parts = line.trim().split(/\s+/).slice(1).map(Number);
        if (parts.length < 4) return;

        const idle = parts[3] + (parts[4] || 0); // idle + iowait
        const total = parts.reduce(function(a, b) { return a + b; }, 0);

        if (root._lastCpu) {
            const deltaTotal = total - root._lastCpu.total;
            const deltaIdle = idle - root._lastCpu.idle;
            if (deltaTotal > 0) {
                root.cpuUsage = Math.max(0, Math.min(1, 1 - (deltaIdle / deltaTotal)));
            }
        }
        root._lastCpu = { total: total, idle: idle };
    }

    function _parseMem(text) {
        const lines = text.split("\n");
        let totalKb = 0, availKb = 0;
        for (const line of lines) {
            if (line.indexOf("MemTotal:") === 0) totalKb = parseInt(line.replace(/\D/g, ""));
            if (line.indexOf("MemAvailable:") === 0) availKb = parseInt(line.replace(/\D/g, ""));
        }
        if (totalKb > 0) {
            root.memTotalGb = totalKb / 1048576;
            root.memUsedGb = (totalKb - availKb) / 1048576;
            root.memUsage = Math.max(0, Math.min(1, (totalKb - availKb) / totalKb));
        }
    }

    function _parseDisk(text) {
        const lines = text.trim().split("\n");
        if (lines.length < 2) return;
        const parts = lines[1].trim().split(/\s+/);
        const totalBytes = parseFloat(parts[1]);
        const usedBytes = parseFloat(parts[2]);
        if (totalBytes > 0) {
            root.diskTotalGb = totalBytes / 1073741824;
            root.diskUsedGb = usedBytes / 1073741824;
            root.diskUsage = usedBytes / totalBytes;
        }
    }

    Component.onCompleted: refresh()
}
