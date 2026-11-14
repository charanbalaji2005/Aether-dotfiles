pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// Screen recording via the `aether-record` helper (wf-recorder).
//
// The helper owns the recorder process and its PID file in
// $XDG_RUNTIME_DIR, so recording survives a shell restart and the
// indicator re-appears correctly afterwards. While recording, status is
// re-checked every 5 s (to notice a recorder that died); elapsed time is
// computed locally from the start time.
Singleton {
    id: root

    property bool available: false
    property bool recording: false
    property string file: ""
    property real _startedAt: 0
    property int seconds: 0
    property string lastError: ""
    property bool withAudio: false

    function _apply(text) {
        try {
            const s = JSON.parse(text.trim().split("\n").pop());
            root.available = s.available === true;
            const was = root.recording;
            root.recording = s.recording === true;
            root.file = s.file || "";
            if (root.recording && !was) root._startedAt = Date.now() - (s.seconds || 0) * 1000;
            if (!root.recording && was) {
                EventBus.islandEvent("recording", { text: "Recording saved", file: root.file });
            }
        } catch (e) {
            Logger.warn("RecordingService", "aether-record status was not valid JSON: " + String(e));
        }
    }

    Process {
        id: status
        command: Paths.helper("aether-record", ["status"])
        stdout: StdioCollector { onStreamFinished: root._apply(this.text) }
    }
    Process {
        id: control
        stdout: StdioCollector { onStreamFinished: root._apply(this.text) }
        stderr: StdioCollector { onStreamFinished: { const e = this.text.trim(); if (e.length) { root.lastError = e; Logger.warn("RecordingService", e); } } }
        onExited: status.running = true
    }

    function start(mode) {
        if (root.recording || control.running) return;
        root.lastError = "";
        control.command = Paths.helper("aether-record", ["start", mode === "region" ? "region" : "full"].concat(root.withAudio ? ["--audio"] : []));
        control.running = true;
    }
    function stop() {
        if (control.running) return;
        control.command = Paths.helper("aether-record", ["stop"]);
        control.running = true;
    }
    function toggle(mode) { if (root.recording) stop(); else start(mode); }

    Timer {
        interval: 1000; repeat: true; running: root.recording
        onTriggered: root.seconds = Math.round((Date.now() - root._startedAt) / 1000)
    }
    Timer {
        interval: 5000; repeat: true; running: root.recording
        onTriggered: status.running = true
    }

    Component.onCompleted: status.running = true
}
