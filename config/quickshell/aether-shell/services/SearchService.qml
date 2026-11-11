pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// File search for the launcher ("/query").
// plocate when installed (indexed, instant), otherwise a bounded scan of
// your home folder (depth 5, hidden folders skipped, first 30 results,
// 3 s timeout). The query is always a positional argument — never part of
// a shell string — and a search only starts 250 ms after you stop typing.
Singleton {
    id: root

    property var results: []      // [{ path, name, dir }]
    property bool searching: false
    property string backend: ""
    property string _pending: ""

    Process {
        id: probe
        command: ["sh", "-c", "command -v plocate >/dev/null && echo plocate || echo find"]
        stdout: StdioCollector { onStreamFinished: root.backend = this.text.trim() }
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                const home = Quickshell.env("HOME") || "";
                root.results = this.text.split("\n").filter(function(l) { return l.length > 0 && l.indexOf("/.") < 0; }).slice(0, 30).map(function(p) {
                    const i = p.lastIndexOf("/");
                    return { path: p, name: p.substring(i + 1), dir: p.substring(0, i).replace(home, "~") };
                });
                root.searching = false;
            }
        }
        onExited: root.searching = false
    }

    Timer {
        id: debounce
        interval: 250
        onTriggered: {
            const q = root._pending;
            if (q.length < 2) { root.results = []; return; }
            const home = Quickshell.env("HOME") || "/";
            proc.command = root.backend === "plocate"
                ? ["plocate", "-i", "-l", "60", "--", q]
                : ["timeout", "3", "find", home, "-maxdepth", "5", "-not", "-path", "*/.*", "-iname", "*" + q.replace(/[\\*?\[\]]/g, "") + "*", "-print"];
            root.searching = true;
            proc.running = true;
        }
    }

    function search(q) {
        root._pending = q;
        debounce.restart();
    }

    function open(path) {
        if (!path || path.charAt(0) !== "/") return;
        Quickshell.execDetached(["xdg-open", path]);
    }

    Component.onCompleted: probe.running = true
}
