import QtQuick
import Quickshell.Io
import "../../../core"

// Runs `aether logs` (already redacted) and hands back the text.
Process {
    id: p
    signal done(string text)
    command: Paths.aether(["logs", "--lines", "60"])
    stdout: StdioCollector { onStreamFinished: p.done(this.text) }
}
