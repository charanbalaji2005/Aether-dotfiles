pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// Every mapped window, from `hyprctl -j clients`, refreshed on the Hyprland
// IPC events that change it (debounced: a burst of events = one query).
// Nothing polls while windows aren't changing.
//
// Used by the overview, the dock (running apps), smart layouts and
// automation (app opened/closed triggers). Diffing successive snapshots
// gives `windowOpened`/`windowClosed` with the window's class, which the
// raw closewindow event doesn't carry.
Singleton {
    id: root

    readonly property bool available: HyprlandService.available
    property var clients: []            // [{address, class, title, workspace, monitor, at, size, floating, fullscreen, pid, focusHistoryID}]
    property string activeAddress: ""
    readonly property var activeClient: clients.find(function(c) { return c.address === root.activeAddress; }) || null
    readonly property bool fullscreenActive: activeClient !== null && (activeClient.fullscreen === true || activeClient.fullscreen > 0)
    // Distinct running app classes, most recently focused first.
    readonly property var runningClasses: {
        const seen = {}, out = [];
        const sorted = clients.slice().sort(function(a, b) { return a.focusHistoryID - b.focusHistoryID; });
        for (const c of sorted) if (c.class && !seen[c.class]) { seen[c.class] = true; out.push(c.class); }
        return out;
    }

    signal windowOpened(string cls, string title, string address)
    signal windowClosed(string cls, string address)

    readonly property var _events: ["openwindow", "closewindow", "movewindow", "movewindowv2", "windowtitle", "windowtitlev2",
        "changefloatingmode", "fullscreen", "activewindowv2", "workspace", "workspacev2", "moveworkspace", "focusedmon", "pin"]

    Process {
        id: query
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list;
                try { list = JSON.parse(this.text); } catch (e) { return; }
                if (!Array.isArray(list)) return;
                const next = list.filter(function(c) { return c && c.mapped !== false && /^0x[0-9a-fA-F]+$/.test(c.address || ""); })
                    .map(function(c) {
                        return {
                            address: c.address, class: c.class || c.initialClass || "", title: c.title || "",
                            workspace: c.workspace ? c.workspace.id : -1, workspaceName: c.workspace ? (c.workspace.name || "") : "",
                            monitor: c.monitor, at: c.at || [0, 0], size: c.size || [0, 0], floating: !!c.floating,
                            fullscreen: c.fullscreen, pid: c.pid, focusHistoryID: c.focusHistoryID === undefined ? 99 : c.focusHistoryID,
                            pinned: !!c.pinned
                        };
                    });
                root._diff(root.clients, next);
                root.clients = next;
                const active = next.find(function(c) { return c.focusHistoryID === 0; });
                root.activeAddress = active ? active.address : "";
            }
        }
    }

    property bool _primed: false
    function _diff(prev, next) {
        if (!root._primed) { root._primed = true; return; }   // first snapshot: nothing "opened"
        const before = {}, after = {};
        for (const c of prev) before[c.address] = c;
        for (const c of next) after[c.address] = c;
        for (const a in after) if (!before[a]) root.windowOpened(after[a].class, after[a].title, a);
        for (const a in before) if (!after[a]) root.windowClosed(before[a].class, a);
    }

    Timer {
        id: debounce
        interval: 90
        onTriggered: if (root.available) query.running = true
    }

    function refresh() { debounce.restart(); }

    Connections {
        target: root.available ? Hyprland : null
        function onRawEvent(event) {
            if (event && root._events.indexOf(event.name) >= 0) debounce.restart();
        }
    }

    // ── Actions (all validated: addresses come from our own snapshot) ──
    function _known(address) { return root.clients.some(function(c) { return c.address === address; }); }

    function focus(address) {
        if (!_known(address)) return;
        HyprlandService.dispatch("focuswindow address:" + address);
    }
    function close(address) {
        if (!_known(address)) return;
        HyprlandService.dispatch("closewindow address:" + address);
    }
    function moveToWorkspace(address, workspaceId, follow) {
        const ws = parseInt(workspaceId);
        if (!_known(address) || !(ws >= 1 && ws <= 99)) return;
        HyprlandService.dispatch((follow ? "movetoworkspace " : "movetoworkspacesilent ") + ws + ",address:" + address);
        debounce.restart();
    }
    function toggleFloating(address) {
        if (!_known(address)) return;
        HyprlandService.dispatch("togglefloating address:" + address);
    }
    function windowsOn(workspaceId) {
        return root.clients.filter(function(c) { return c.workspace === workspaceId; });
    }
    function windowsOfClass(cls) {
        return root.clients.filter(function(c) { return c.class === cls; });
    }
    // Focus the most recent window of an app; returns false if none is open.
    function focusClass(cls) {
        const list = root.windowsOfClass(cls).sort(function(a, b) { return a.focusHistoryID - b.focusHistoryID; });
        if (list.length === 0) return false;
        root.focus(list[0].address);
        return true;
    }

    Component.onCompleted: if (available) query.running = true
}
