pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// Runs `aether … --json` commands for the UI, one at a time per caller tag,
// and hands back parsed JSON. Arguments are always an argv list (never a
// shell string), so nothing in them can be interpreted as shell syntax.
//
//   CliService.run("updates", ["updates", "--json"], function(ok, data, err) { ... })
//
// A newer request with the same tag replaces a queued one (the UI only
// cares about the latest answer).
Singleton {
    id: root

    property var _queue: []
    property var _current: null
    property var busy: ({})

    function run(tag, args, callback) {
        root._queue = root._queue.filter(function(q) { return q.tag !== tag; }).concat([{ tag: tag, args: args, cb: callback }]);
        const b = Object.assign({}, root.busy); b[tag] = true; root.busy = b;
        if (!proc.running && !root._current) root._next();
    }
    function isBusy(tag) { return root.busy[tag] === true; }

    function _next() {
        if (root._queue.length === 0) { root._current = null; return; }
        root._current = root._queue[0];
        root._queue = root._queue.slice(1);
        root._code = -1; root._outDone = false; root._errDone = false;
        proc.command = Paths.aether(root._current.args);
        proc.running = true;
    }

    // Completion needs both the exit code and the end of stdout: Quickshell
    // doesn't order those two signals, so each records its half.
    property int _code: -1
    property bool _outDone: false
    property bool _errDone: false
    property string _outText: ""
    property string _errText: ""

    function _maybeFinish() {
        if (root._code < 0 || !root._outDone || !root._errDone || !root._current) return;
        const job = root._current;
        let data = null;
        // Non-JSON output is reported to the caller as a failure below (ok=false).
        try { data = JSON.parse(root._outText); } catch (e) { data = null; }
        const b = Object.assign({}, root.busy); delete b[job.tag]; root.busy = b;
        const ok = root._code === 0 && data !== null;
        if (job.cb) {
            try { job.cb(ok, data, root._errText.trim() || (data === null ? "no output (exit " + root._code + ")" : "")); }
            catch (e) { Logger.warn("CliService", job.tag + " callback failed: " + e); }
        }
        root._current = null;
        root._next();
    }

    Process {
        id: proc
        onStarted: { root._code = -1; root._outDone = false; root._errDone = false; root._outText = ""; root._errText = ""; }
        stdout: StdioCollector { onStreamFinished: { root._outText = this.text; root._outDone = true; root._maybeFinish(); } }
        stderr: StdioCollector { onStreamFinished: { root._errText = this.text; root._errDone = true; root._maybeFinish(); } }
        onExited: function(code) { root._code = code; root._maybeFinish(); }
    }
}
