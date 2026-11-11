pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// Data for the System Centre: updates, security posture, user services,
// snapshots. Everything is fetched on demand when a tab opens — nothing
// here runs in the background. Package updates are only listed; installing
// opens a terminal running `sudo dnf upgrade --refresh` so the user sees
// and approves the transaction (no silent privilege use).
Singleton {
    id: root

    property var updates: null
    property var security: null
    property var services: null
    property var snapshots: []
    property var serviceLog: ({ unit: "", text: "" })
    property string error: ""

    function loadUpdates() { CliService.run("updates", ["updates", "--json"], function(ok, d, e) { root.updates = d || { available: false, reason: e }; }); }
    function loadSecurity() { CliService.run("security", ["security", "--json"], function(ok, d, e) { root.security = d; if (!ok) root.error = e; }); }
    function loadServices() { CliService.run("services", ["services", "list", "--json"], function(ok, d, e) { root.services = d || { available: false, reason: e }; }); }
    function loadSnapshots() { CliService.run("snapshots", ["snapshot", "list", "--json"], function(ok, d, e) { root.snapshots = ok ? d : []; }); }

    function serviceAction(action, unit) {
        if (["start", "stop", "restart"].indexOf(action) < 0) return;
        CliService.run("svc-" + unit, ["services", action, unit, "--json"], function(ok, d, e) {
            root.error = ok ? "" : ((d && d.error) || e);
            root.loadServices();
        });
    }
    function loadLog(unit) {
        CliService.run("svc-log", ["services", "log", unit, "--lines", "60", "--json"], function(ok, d, e) {
            root.serviceLog = { unit: unit, text: ok ? d.log : ((d && d.error) || e) };
        });
    }
    function createSnapshot() {
        CliService.run("snap-create", ["snapshot", "create", "--label", "manual", "--json"], function(ok, d, e) {
            root.error = ok ? "" : e;
            root.loadSnapshots();
        });
    }
    function markGood() { CliService.run("snap-good", ["snapshot", "mark-good", "--json"], function() { root.loadSnapshots(); }); }
    function restoreSnapshot(name) {
        CliService.run("snap-restore", ["snapshot", "restore", name, "--yes", "--json"], function(ok, d, e) {
            root.error = ok && d.ok ? "" : ((d && d.problems ? d.problems.join("; ") : e));
            if (ok && d.ok) EventBus.notificationRequested("Settings restored", d.restored.length + " file(s) from " + name, "normal");
            root.loadSnapshots();
        });
    }

    // Opens the preferred terminal (aether-terminal) running the upgrade, so
    // sudo asks for the password there and the transaction is visible.
    function runUpgrade() {
        Quickshell.execDetached(Paths.helper("aether-terminal", ["-e", "sudo", "dnf", "upgrade", "--refresh"]));
    }

    // Process control for the process tab: only the user's own processes
    // can be signalled (kill(2) enforces that anyway; no privilege is used).
    Process { id: killer }
    function terminate(pid, force) {
        const p = parseInt(pid);
        if (!(p > 1)) return;
        killer.command = ["kill", force ? "-KILL" : "-TERM", String(p)];
        killer.running = true;
    }
}
