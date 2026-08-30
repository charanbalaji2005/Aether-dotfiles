pragma Singleton
import Quickshell
import Quickshell.Io
import "../core"

// Wraps `cliphist` (the standard wl-clipboard-based history daemon used
// across Hyprland/wlroots setups) rather than implementing a clipboard
// history daemon from scratch. If cliphist isn't installed, `available`
// stays false and the clipboard history UI reports it plainly.
Singleton {
    id: root

    property bool available: false
    property var entries: [] // [{raw, preview}] — raw is cliphist's own line, needed verbatim for decode/delete

    Process {
        id: listProcess
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: root._parseList(this.text)
        }
    }

    Process { id: copyProcess }
    Process { id: deleteProcess }
    Process { id: wipeProcess }

    function refresh() {
        listProcess.running = true;
    }

    function _parseList(text) {
        root.available = true;
        const lines = text.split("\n").filter(function(l) { return l.trim().length > 0; });
        root.entries = lines.map(function(line) {
            const tab = line.indexOf("\t");
            return {
                raw: line,
                preview: tab >= 0 ? line.substring(tab + 1) : line
            };
        });
    }

    // entry.raw is passed as $1 (a real argv element, never string-interpolated
    // into the script) so arbitrary clipboard content can never break out of
    // the shell command.
    function copyEntry(entry) {
        if (!entry) return;
        copyProcess.command = ["bash", "-c", 'cliphist decode <<< "$1" | wl-copy', "_", entry.raw];
        copyProcess.running = true;
    }

    function deleteEntry(entry) {
        if (!entry) return;
        deleteProcess.command = ["bash", "-c", 'cliphist delete <<< "$1"', "_", entry.raw];
        deleteProcess.running = true;
        root.entries = root.entries.filter(function(e) { return e.raw !== entry.raw; });
    }

    function wipe() {
        wipeProcess.command = ["cliphist", "wipe"];
        wipeProcess.running = true;
        root.entries = [];
    }

    Component.onCompleted: refresh()
}
