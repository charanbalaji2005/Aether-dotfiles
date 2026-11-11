pragma Singleton
import QtQuick
import Quickshell
import "../core"

// Widget catalogue (`aether widget list --json`: built-in + user-installed,
// each statically validated) and the placed instances in Config.widgets.placed.
Singleton {
    id: root

    property var catalog: []        // [{id, name, valid, permissions, size, path, entry, problems}]
    property bool editing: false

    function refresh() {
        CliService.run("widgets", ["widget", "list", "--json"], function(ok, d) { if (ok) root.catalog = d; });
    }
    function info(widgetId) { return root.catalog.find(function(w) { return w.id === widgetId; }) || null; }

    function place(widgetId, screenName) {
        const w = root.info(widgetId);
        if (!w || !w.valid) return;
        const list = (Config.widgets.placed || []).slice();
        const n = list.filter(function(p) { return p.screen === screenName; }).length;
        list.push({ id: widgetId + "-" + Date.now().toString(36), widget: widgetId, screen: screenName,
                    x: 48 + (n % 4) * 40, y: 96 + (n % 4) * 40, w: w.size ? w.size.w : 240, h: w.size ? w.size.h : 160 });
        Config.widgets.placed = list;
        Config.widgets.enabled = true;
    }
    function move(instanceId, x, y) {
        const g = Math.max(4, Config.widgets.grid);
        Config.widgets.placed = (Config.widgets.placed || []).map(function(p) {
            return p.id === instanceId ? Object.assign({}, p, { x: Math.max(0, Math.round(x / g) * g), y: Math.max(0, Math.round(y / g) * g) }) : p;
        });
    }
    function remove(instanceId) {
        Config.widgets.placed = (Config.widgets.placed || []).filter(function(p) { return p.id !== instanceId; });
    }

    Component.onCompleted: refresh()
}
