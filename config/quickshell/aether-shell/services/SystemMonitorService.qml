pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// Live system telemetry for the bar and dashboard.
//
// Primary source: ONE long-lived `aether telemetry --stream` process (Python,
// lib/aether/telemetry.py) that prints a JSON line per interval. That
// replaces forking cat/df every two seconds, discovers sensors once, never
// wakes a sleeping hybrid dGPU, and reports `null` + a reason for anything
// it can't read.
//
// Fallback: if the backend can't run (python3 missing, repo moved), the
// original /proc polling keeps CPU/RAM/disk working and GPU/temperature
// metrics are marked unavailable — never invented.
//
// Public API is backwards compatible with the Phase 5 service
// (cpuUsage/memUsage/memUsedGb/... ) plus the new metrics below.
Singleton {
    id: root

    // ── Compatible API ──────────────────────────────────────────────────
    property real cpuUsage: 0   // 0-1
    property real memUsage: 0   // 0-1
    property real memUsedGb: 0
    property real memTotalGb: 0
    property real diskUsage: 0  // 0-1
    property real diskUsedGb: 0
    property real diskTotalGb: 0

    // ── Extended metrics (null/-1 => unavailable) ──────────────────────
    property string source: "starting"        // "telemetry" | "fallback" | "starting"
    property real cpuTemp: -1                 // °C
    property string cpuTempNote: ""
    property real cpuFreqMhz: -1
    property var cpuCores: []                 // per-thread 0-1
    property real swapUsage: 0
    property real swapUsedGb: 0
    property real swapTotalGb: 0
    property var loadAvg: []
    property real uptimeSeconds: -1
    property string netIface: ""
    property real netRxBps: -1
    property real netTxBps: -1
    property var gpus: []                     // see telemetry.py for fields
    // Full GPU counters from the detail stream (only while a process view is
    // open): includes awake hybrid dGPUs and per-GPU process lists (NVML).
    property var gpuDetail: []
    // Emitted after each main telemetry sample (PerformanceService's GPU-pressure policy listens).
    signal sampled()
    readonly property var primaryGpu: _pickGpu(gpus)
    property var processes: []                // filled only while `wantProcesses`

    // History for graphs (oldest first), one sample per interval.
    readonly property int historyLength: 60
    property var cpuHistory: []
    property var memHistory: []
    property var gpuHistory: []
    property var netRxHistory: []
    property var netTxHistory: []

    // Consumers (the dashboard) set this while visible.
    // Reference-counted: the dashboard and the System Centre each hold one
    // while their process list is on screen.
    property int processConsumers: 0
    readonly property bool wantProcesses: processConsumers > 0
    function wantProcessList() { root.processConsumers += 1; }
    function releaseProcessList() { root.processConsumers = Math.max(0, root.processConsumers - 1); }

    readonly property int interval: Math.max(500, Config.performance.telemetryInterval || 2000)
    readonly property real effectiveIntervalSeconds: (ShellState.onBattery && Config.performance.pauseOnBattery ? interval * 2 : interval) / 1000.0

    function _pickGpu(list) {
        if (!list || list.length === 0) return null;
        // Prefer an awake discrete GPU with usage data, else the first one.
        for (const g of list) if (g.kind === "discrete" && g.state === "active" && g.usage !== null) return g;
        for (const g of list) if (g.usage !== null || g.tempC !== null) return g;
        return list[0];
    }

    function _push(arr, v) {
        const next = arr.concat([v]);
        return next.length > root.historyLength ? next.slice(next.length - root.historyLength) : next;
    }

    function _apply(d) {
        root.source = "telemetry";
        if (d.cpu) {
            if (d.cpu.usage !== null && d.cpu.usage !== undefined) {
                root.cpuUsage = d.cpu.usage;
                root.cpuHistory = root._push(root.cpuHistory, d.cpu.usage);
            }
            root.cpuTemp = (d.cpu.tempC === null || d.cpu.tempC === undefined) ? -1 : d.cpu.tempC;
            root.cpuTempNote = d.cpu.tempNote || "";
            root.cpuFreqMhz = d.cpu.freqMhz || -1;
            root.cpuCores = d.cpu.cores || [];
        }
        if (d.mem && d.mem.total) {
            root.memTotalGb = d.mem.total / 1073741824;
            root.memUsedGb = (d.mem.used || 0) / 1073741824;
            root.memUsage = Math.max(0, Math.min(1, (d.mem.used || 0) / d.mem.total));
            root.memHistory = root._push(root.memHistory, root.memUsage);
            root.swapTotalGb = (d.mem.swapTotal || 0) / 1073741824;
            root.swapUsedGb = (d.mem.swapUsed || 0) / 1073741824;
            root.swapUsage = d.mem.swapTotal ? (d.mem.swapUsed || 0) / d.mem.swapTotal : 0;
        }
        if (d.disk && d.disk.total) {
            root.diskTotalGb = d.disk.total / 1073741824;
            root.diskUsedGb = d.disk.used / 1073741824;
            root.diskUsage = d.disk.used / d.disk.total;
        }
        if (d.net) {
            root.netIface = d.net.iface || "";
            root.netRxBps = d.net.rxBps === null ? -1 : d.net.rxBps;
            root.netTxBps = d.net.txBps === null ? -1 : d.net.txBps;
            if (d.net.rxBps !== null) {
                root.netRxHistory = root._push(root.netRxHistory, d.net.rxBps);
                root.netTxHistory = root._push(root.netTxHistory, d.net.txBps);
            }
        }
        if (d.gpus) {
            root.gpus = d.gpus;
            root.sampled();
            const g = root._pickGpu(d.gpus);
            root.gpuHistory = root._push(root.gpuHistory, g && g.usage !== null ? g.usage : 0);
        }
        root.loadAvg = d.load || [];
        root.uptimeSeconds = d.uptime === null || d.uptime === undefined ? -1 : d.uptime;
    }

    // ── Primary: telemetry stream ───────────────────────────────────────
    Process {
        id: stream
        running: true
        command: Paths.aether(["telemetry", "--stream", "--interval", String(root.effectiveIntervalSeconds)])
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    root._apply(JSON.parse(line));
                } catch (e) {
                    Logger.warn("SystemMonitorService", "Bad telemetry line: " + e);
                }
            }
        }
        onExited: function(exitCode, exitStatus) {
            if (root._intentionalRestart) {
                // We stopped it ourselves (interval changed); restartTimer brings it back.
                root._intentionalRestart = false;
                return;
            }
            if (root.source === "telemetry" && root._restarts < 5) {
                // It worked before: transient failure, restart shortly.
                root._restarts += 1;
                Logger.warn("SystemMonitorService", "telemetry stream exited (" + exitCode + "), restarting");
                restartTimer.restart();
            } else {
                Logger.warn("SystemMonitorService", "aether telemetry unavailable (exit " + exitCode + "); using /proc fallback");
                root.source = "fallback";
                root.cpuTempNote = "Install the AetherOS CLI backend (python3) for temperatures and GPU metrics";
            }
        }
    }

    property int _restarts: 0

    Timer {
        id: restartTimer
        interval: 3000
        onTriggered: stream.running = true
    }

    // A stream that has been healthy for a while earns its restart budget back.
    Timer {
        interval: 60000
        running: root._restarts > 0 && stream.running
        onTriggered: root._restarts = 0
    }

    // Restart the stream when the interval setting changes.
    property bool _intentionalRestart: false
    onEffectiveIntervalSecondsChanged: if (stream.running) { root._intentionalRestart = true; stream.running = false; restartTimer.restart(); }

    // ── Processes (dashboard only) ─────────────────────────────────────
    Process {
        id: procStream
        running: root.wantProcesses && root.source === "telemetry"
        command: Paths.aether(["telemetry", "--stream", "--processes", "--interval", String(Math.max(2, root.effectiveIntervalSeconds))])
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    const d = JSON.parse(line);
                    if (d.procs) root.processes = d.procs;
                    if (d.gpus) root.gpuDetail = d.gpus;
                } catch (e) {}
            }
        }
        onRunningChanged: if (!running) { root.processes = []; root.gpuDetail = []; }
    }

    // ── Fallback: direct /proc polling (original implementation) ────────
    property var _lastCpu: null

    Process {
        id: statProcess
        command: ["cat", "/proc/stat"]
        stdout: StdioCollector { onStreamFinished: root._parseCpu(this.text) }
    }
    Process {
        id: memProcess
        command: ["cat", "/proc/meminfo"]
        stdout: StdioCollector { onStreamFinished: root._parseMem(this.text) }
    }
    Process {
        id: diskProcess
        command: ["df", "-B1", "/"]
        stdout: StdioCollector { onStreamFinished: root._parseDisk(this.text) }
    }
    Timer {
        interval: root.interval
        running: root.source === "fallback"
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statProcess.running = true;
            memProcess.running = true;
            diskProcess.running = true;
        }
    }

    function _parseCpu(text) {
        const parts = text.split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
        if (parts.length < 4) return;
        const idle = parts[3] + (parts[4] || 0);
        const total = parts.reduce(function(a, b) { return a + b; }, 0);
        if (root._lastCpu) {
            const dt = total - root._lastCpu.total;
            if (dt > 0) {
                root.cpuUsage = Math.max(0, Math.min(1, 1 - (idle - root._lastCpu.idle) / dt));
                root.cpuHistory = root._push(root.cpuHistory, root.cpuUsage);
            }
        }
        root._lastCpu = { total: total, idle: idle };
    }

    function _parseMem(text) {
        let totalKb = 0, availKb = 0;
        for (const line of text.split("\n")) {
            if (line.indexOf("MemTotal:") === 0) totalKb = parseInt(line.replace(/\D/g, ""));
            if (line.indexOf("MemAvailable:") === 0) availKb = parseInt(line.replace(/\D/g, ""));
        }
        if (totalKb > 0) {
            root.memTotalGb = totalKb / 1048576;
            root.memUsedGb = (totalKb - availKb) / 1048576;
            root.memUsage = Math.max(0, Math.min(1, (totalKb - availKb) / totalKb));
            root.memHistory = root._push(root.memHistory, root.memUsage);
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

    // ── Formatting helpers for the UI ───────────────────────────────────
    function formatRate(bps) {
        if (bps === null || bps === undefined || bps < 0) return "—";
        if (bps < 1024) return Math.round(bps) + " B/s";
        if (bps < 1048576) return (bps / 1024).toFixed(bps < 10240 ? 1 : 0) + " KB/s";
        return (bps / 1048576).toFixed(1) + " MB/s";
    }

    function formatBytes(b) {
        if (b === null || b === undefined || b < 0) return "—";
        if (b < 1073741824) return (b / 1048576).toFixed(0) + " MB";
        return (b / 1073741824).toFixed(1) + " GB";
    }

    function formatUptime(s) {
        if (s === null || s === undefined || s < 0) return "—";
        const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
        return (d > 0 ? d + "d " : "") + h + "h " + m + "m";
    }
}
