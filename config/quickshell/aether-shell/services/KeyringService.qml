pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// Stores an API key in the desktop keyring via `aether ai set-key`, writing
// the key to the process's stdin (never argv). The key is held only for the
// duration of the write; nothing in the shell keeps it.
Singleton {
    id: root
    property var _cb: null
    property string _key: ""
    Process {
        id: proc
        stdinEnabled: true
        stderr: StdioCollector { id: err }
        onStarted: { proc.write(root._key); root._key = ""; proc.stdinEnabled = false; }
        onExited: function(code) {
            proc.stdinEnabled = true;
            if (root._cb) root._cb(code === 0, err.text.trim() || "the keyring refused the key");
            root._cb = null;
        }
    }
    function store(provider, key, cb) {
        if (!key || proc.running) { if (cb) cb(false, "empty key"); return; }
        root._key = key;
        root._cb = cb;
        proc.command = Paths.aether(["ai", "set-key", "--provider", provider]);
        proc.running = true;
    }
}
