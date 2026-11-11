pragma Singleton
import QtQuick
import Quickshell
import "../core"

// Desktop profiles (`aether profile …`): bundles of appearance settings.
// Applying one snapshots the current settings first, so it can be undone
// from Settings → Profiles or `aether snapshot restore`.
Singleton {
    id: root

    property var profiles: []
    property string lastApplied: ""
    property string lastUndo: ""
    property string error: ""

    function refresh() {
        CliService.run("profiles", ["profile", "list", "--json"], function(ok, data, err) {
            if (ok) root.profiles = data; else root.error = err;
        });
    }
    function apply(name) {
        CliService.run("profile-apply", ["profile", "apply", name, "--json"], function(ok, data, err) {
            if (ok && data.ok) {
                root.lastApplied = name;
                root.lastUndo = data.undo || "";
                root.error = "";
                EventBus.notificationRequested("Profile applied", name, "low");
            } else {
                root.error = (data && data.error) || err;
            }
        });
    }
    function saveCurrent(name, label) {
        CliService.run("profile-save", ["profile", "save", name, "--label", label || name, "--json"], function(ok, data, err) {
            root.error = ok && data.ok ? "" : ((data && data.error) || err);
            root.refresh();
        });
    }
    function undo() {
        if (!root.lastUndo) return;
        const name = root.lastUndo.split("/").pop().replace(/\.tar\.gz$/, "");
        CliService.run("snapshot-restore", ["snapshot", "restore", name, "--yes", "--json"], function(ok, data, err) {
            root.error = ok ? "" : err;
            if (ok) root.lastUndo = "";
        });
    }
}
