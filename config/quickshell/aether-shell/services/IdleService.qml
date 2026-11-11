pragma Singleton
import QtQuick
import Quickshell
import "../core"

// Keeps hypridle's configuration in step with Settings → Lock screen:
// on change (debounced) it runs `aether idle apply`, which rewrites
// ~/.config/aether-shell/hypr/hypridle.conf and restarts aether-idle.service.
Singleton {
    id: root

    readonly property string key: [Config.lock.idleLockMinutes, Config.lock.idleDisplayOffMinutes, Config.lock.idleSuspendMinutes, Config.power.dimAfterMinutes].join(",")
    property string _applied: ""
    property bool _ready: false

    onKeyChanged: if (root._ready) debounce.restart()
    Timer {
        id: debounce
        interval: 1200
        onTriggered: {
            if (root.key === root._applied) return;
            root._applied = root.key;
            CliService.run("idle", ["idle", "apply", "--json"], function(ok, d, e) {
                if (!ok) Logger.warn("IdleService", "aether idle apply failed: " + e);
                else if (d && d.hypridle === false) Logger.warn("IdleService", "hypridle not installed: idle locking inactive");
            });
        }
    }
    Connections {
        target: Config
        function onReadyChanged() { if (Config.ready) { root._applied = root.key; root._ready = true; } }
    }
}
