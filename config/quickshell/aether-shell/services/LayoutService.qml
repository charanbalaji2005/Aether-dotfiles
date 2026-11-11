pragma Singleton
import QtQuick
import Quickshell
import "../core"

// Smart window layouts (`aether layout …`). The backend reads real monitor
// geometry and window classes from Hyprland, validates every dispatch and
// records an undo; this service just drives it.
Singleton {
    id: root

    property var layouts: []
    property var preview: null
    property var lastResult: null
    property string error: ""

    function refresh() {
        CliService.run("layouts", ["layout", "list", "--json"], function(ok, data, err) { if (ok) root.layouts = data; else root.error = err; });
    }
    function previewLayout(name) {
        root.preview = null;
        CliService.run("layout-preview", ["layout", "preview", name, "--json"], function(ok, data, err) {
            root.preview = data; root.error = ok ? "" : ((data && data.error) || err);
        });
    }
    function apply(name, launch) {
        CliService.run("layout-apply", ["layout", "apply", name, "--json"].concat(launch === false ? ["--no-launch"] : []), function(ok, data, err) {
            root.lastResult = data;
            root.error = data && data.errors && data.errors.length ? data.errors.join("; ") : (ok ? "" : ((data && data.error) || err));
            if (data && data.placed) EventBus.notificationRequested("Layout applied", (data.placed.length) + " window(s) arranged" + (data.skipped && data.skipped.length ? "; " + data.skipped.length + " skipped" : ""), "low");
        });
    }
    function undo() {
        CliService.run("layout-undo", ["layout", "undo", "--json"], function(ok, data, err) { root.error = ok ? "" : ((data && data.error) || err); });
    }
    function saveCurrent(name) {
        CliService.run("layout-save", ["layout", "save", name, "--json"], function(ok, data, err) {
            root.error = ok ? "" : ((data && data.error) || err);
            root.refresh();
        });
    }
}
