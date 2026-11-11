pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// Audio spectrum from cava, for the island's visualiser and audio-reactive
// effects.
//
// Capture: cava's PipeWire input on the default *output's* monitor — what
// you hear. The microphone is never captured. cava runs only while some
// consumer is visible AND media is playing, at 30 fps, and is stopped the
// moment either stops being true (`demand` is reference-counted by
// consumers via want()/release()).
//
// Exposes `bars` (0-1 each), and smoothed `bass`, `mid`, `treble`, `level`.
Singleton {
    id: root

    property int barCount: 24
    property var bars: []
    property real bass: 0
    property real mid: 0
    property real treble: 0
    property real level: 0
    property int demand: 0
    property bool available: false
    readonly property bool active: cava.running

    readonly property bool shouldRun: available && demand > 0 && MediaService.playing && Config.island.visualizer
        && PerformanceService.tier !== "eco" && PerformanceService.ambient
    readonly property string confPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/aether-cava.conf"

    function want() { root.demand += 1; }
    function release() { root.demand = Math.max(0, root.demand - 1); }

    readonly property string _conf: [
        "[general]", "bars = " + root.barCount, "framerate = 30", "autosens = 1",
        "[input]", "method = pipewire", "source = auto",
        "[output]", "method = raw", "raw_target = /dev/stdout", "data_format = ascii",
        "ascii_max_range = 100", "bar_delimiter = 59", "frame_delimiter = 10",
        "[smoothing]", "noise_reduction = 60"
    ].join("\n") + "\n"

    Process {
        id: probe
        command: ["sh", "-c", "command -v cava >/dev/null && printf '%s' \"$1\" > \"$2\"", "sh", root._conf, root.confPath]
        onExited: function(code) { root.available = code === 0; if (code !== 0) Logger.info("VisualizerService", "cava not installed: visualiser unavailable"); }
    }

    Process {
        id: cava
        running: root.shouldRun
        command: ["cava", "-p", root.confPath]
        stdout: SplitParser {
            onRead: function(line) {
                const parts = line.split(";");
                const n = Math.min(root.barCount, parts.length);
                if (n < 4) return;
                const out = new Array(n);
                for (let i = 0; i < n; i++) out[i] = Math.min(1, (parseInt(parts[i]) || 0) / 100);
                root.bars = out;
                const third = Math.floor(n / 3);
                const avg = function(a, b) { let s = 0; for (let i = a; i < b; i++) s += out[i]; return s / Math.max(1, b - a); };
                // Light smoothing so effects pulse instead of flicker.
                root.bass = root.bass * 0.5 + avg(0, third) * 0.5;
                root.mid = root.mid * 0.5 + avg(third, 2 * third) * 0.5;
                root.treble = root.treble * 0.5 + avg(2 * third, n) * 0.5;
                root.level = root.level * 0.6 + avg(0, n) * 0.4;
            }
        }
        onRunningChanged: if (!running) { root.bars = []; root.bass = 0; root.mid = 0; root.treble = 0; root.level = 0; }
    }

    Component.onCompleted: probe.running = true
}
