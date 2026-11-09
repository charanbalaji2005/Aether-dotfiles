pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// Static hardware facts (CPU model, GPUs, drivers, memory, storage) from
// `aether hardware --json`. Loaded lazily the first time something asks
// (the dashboard's System card / Settings → About), then cached — this
// information doesn't change while the session runs.
Singleton {
    id: root

    property bool loaded: false
    property bool loading: false
    property bool available: true
    property var data: null

    readonly property string cpuModel: data && data.cpu && data.cpu.model ? data.cpu.model : ""
    readonly property string cpuTopology: data && data.cpu && data.cpu.topology && data.cpu.topology.threads
        ? data.cpu.topology.cores + " cores · " + data.cpu.topology.threads + " threads" : ""
    readonly property var gpus: data && data.gpus ? data.gpus : []
    readonly property string gpuLayout: data && data.gpuTopology ? data.gpuTopology.layout : ""
    readonly property string kernel: data && data.system ? (data.system.kernel || "") : ""
    readonly property string os: data && data.system ? (data.system.os || "") : ""

    Process {
        id: proc
        command: Paths.aether(["hardware", "--json"])
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.data = JSON.parse(this.text);
                    root.loaded = true;
                } catch (e) {
                    root.available = false;
                }
            }
        }
        onExited: function(code) {
            root.loading = false;
            if (code !== 0) root.available = false;
        }
    }

    function ensureLoaded() {
        if (root.loaded || root.loading) return;
        root.loading = true;
        proc.running = true;
    }

    function reload() {
        root.loaded = false;
        ensureLoaded();
    }
}
