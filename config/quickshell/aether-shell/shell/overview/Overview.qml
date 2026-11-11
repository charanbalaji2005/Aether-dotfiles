import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"
import "../../core"
import "../../services"
import "../../components"
import "../../animation"

// Mission Control: every monitor, workspace and window, drawn at the
// windows' real positions from Hyprland's own geometry.
//
//   SUPER+O            overview (all monitors)
//   SUPER+SHIFT+O      exposé: windows of the focused app
//   3-finger swipe up  overview (Settings → Gestures)
//
// Click a window to focus it · drag it onto another workspace (or the
// "new" card) to move it · × twice to close · double-click a workspace
// title to rename it · type to search · ←/→/↑/↓ + Enter · 1-9 switch
// workspace · Esc close.
//
// Hyprland destroys empty workspaces by itself when you leave them, so
// there is no "delete workspace" button — the "new" card creates one.
Scope {
    id: root

    property bool open: false
    property string mode: "all"         // "all" | "app" | "workspace"
    property string query: ""
    property var monitors: []           // from hyprctl -j monitors
    property var workspaceNames: ({})   // id -> name
    property int selected: 0
    property string armedClose: ""
    property string dragAddress: ""
    property int dropTarget: -1         // workspace id under a drag, 0 = new
    property bool refreshTick: false

    function show(m) {
        root.mode = m || "all";
        root.query = "";
        root.selected = 0;
        root.armedClose = "";
        EventBus.closePopups("aether-overview");
        WindowService.refresh();
        monitorsProc.running = true;
        workspacesProc.running = true;
        root.open = true;
    }
    function hide() { root.open = false; }
    function toggle(m) { if (root.open && root.mode === (m || "all")) hide(); else show(m); }

    Process {
        id: monitorsProc
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector { onStreamFinished: { try { root.monitors = JSON.parse(this.text); } catch (e) {} } }
    }
    Process {
        id: workspacesProc
        command: ["hyprctl", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const names = {};
                    for (const w of JSON.parse(this.text)) names[w.id] = w.name;
                    root.workspaceNames = names;
                } catch (e) {}
            }
        }
    }
    Process { id: renameProc }

    // Logical geometry of a monitor (Hyprland reports physical pixels).
    function logical(m) {
        const s = m.scale || 1;
        const rot = (m.transform || 0) % 2 === 1;
        return { x: m.x, y: m.y, w: (rot ? m.height : m.width) / s, h: (rot ? m.width : m.height) / s };
    }

    readonly property var activeClass: WindowService.activeClient ? WindowService.activeClient.class : ""
    readonly property var focusedMonitorName: HyprlandService.focusedMonitor ? HyprlandService.focusedMonitor.name : ""

    // Groups: [{ monitor, geo, workspaces: [{ id, name, windows: [...] }] }]
    readonly property var groups: {
        const out = [];
        const ws = HyprlandService.workspaces && HyprlandService.workspaces.values ? HyprlandService.workspaces.values : [];
        for (const m of root.monitors) {
            if (root.mode === "workspace" && m.name !== root.focusedMonitorName) continue;
            const geo = root.logical(m);
            const ids = ws.filter(function(w) { return w && w.id > 0 && w.monitor && w.monitor.name === m.name; })
                          .map(function(w) { return w.id; }).sort(function(a, b) { return a - b; });
            if (m.activeWorkspace && ids.indexOf(m.activeWorkspace.id) < 0 && m.activeWorkspace.id > 0) ids.push(m.activeWorkspace.id);
            const list = ids.map(function(id) {
                const custom = (Config.workspaces.names || {})[String(id)];
                return { id: id, name: custom || root.workspaceNames[id] || String(id), icon: (Config.workspaces.icons || {})[String(id)] || "",
                         active: m.activeWorkspace && m.activeWorkspace.id === id,
                         windows: WindowService.windowsOn(id) };
            });
            out.push({ monitor: m.name, geo: geo, focused: m.focused, workspaces: list });
        }
        return out;
    }

    // Flat list of windows in display order, for keyboard navigation.
    readonly property var flatWindows: {
        if (root.mode === "app") return WindowService.windowsOfClass(root.activeClass);
        const out = [];
        for (const g of root.groups) for (const w of g.workspaces) for (const c of w.windows) out.push(c);
        return out;
    }
    function matches(c) {
        if (root.query.length === 0) return true;
        const q = root.query.toLowerCase();
        return (c.title || "").toLowerCase().indexOf(q) >= 0 || (c.class || "").toLowerCase().indexOf(q) >= 0;
    }
    readonly property var visibleWindows: flatWindows.filter(matches)
    readonly property string selectedAddress: visibleWindows.length > 0 ? visibleWindows[Math.min(selected, visibleWindows.length - 1)].address : ""

    function activate(c) {
        if (!c) return;
        root.hide();
        WindowService.focus(c.address);
    }
    function requestClose(address) {
        if (root.armedClose === address) { WindowService.close(address); root.armedClose = ""; }
        else { root.armedClose = address; disarm.restart(); }
    }
    Timer { id: disarm; interval: 3000; onTriggered: root.armedClose = "" }

    function nextFreeWorkspace() {
        const used = {};
        for (const c of WindowService.clients) used[c.workspace] = true;
        const ws = HyprlandService.workspaces && HyprlandService.workspaces.values ? HyprlandService.workspaces.values : [];
        for (const w of ws) used[w.id] = true;
        for (let i = 1; i < 100; i++) if (!used[i]) return i;
        return -1;
    }
    function drop(address, wsId) {
        if (!address) return;
        const target = wsId === 0 ? root.nextFreeWorkspace() : wsId;
        if (target > 0) WindowService.moveToWorkspace(address, target, false);
    }
    function rename(id, name) {
        const clean = name.replace(/[^\w .:@+\-]/g, "").substring(0, 32).trim();
        // Persisted in Settings → Workspaces, so the name survives restarts.
        const m = Object.assign({}, Config.workspaces.names || {});
        if (clean.length) m[String(id)] = clean; else delete m[String(id)];
        Config.workspaces.names = m;
        if (clean.length === 0) return;
        renameProc.command = ["hyprctl", "dispatch", "renameworkspace", String(id) + " " + clean];
        renameProc.running = true;
        renameRefresh.restart();
    }
    Timer { id: renameRefresh; interval: 200; onTriggered: workspacesProc.running = true }

    Connections {
        target: EventBus
        function onOverviewRequested(m) { root.toggle(m); }
        function onClosePopups(except) { if (except !== "aether-overview" && root.open) root.hide(); }
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { root.toggle("all"); }
        function show(): void { root.show("all"); }
        function app(): void { root.toggle("app"); }
        function workspace(): void { root.toggle("workspace"); }
    }

    SpringValue { id: reveal; preset: "smooth"; target: root.open ? 1 : 0 }

    PanelWindow {
        id: win
        visible: root.open || reveal.value > 0.01
        screen: ShellState.activeScreen ? ShellState.activeScreen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
        WlrLayershell.namespace: "aether-overview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: Colors.withAlpha(Colors.bg0, 0.55 * reveal.value)
        }
        MouseArea { anchors.fill: parent; onClicked: root.hide() }

        Item {
            id: stage
            anchors.fill: parent
            anchors.margins: Metrics.spaceXxl
            opacity: Math.min(1, reveal.value * 1.4)
            // Zoom-out: the desktop "recedes" into the grid.
            scale: 1.06 - 0.06 * reveal.value
            focus: root.open

            Keys.onEscapePressed: root.hide()
            Keys.onReturnPressed: root.activate(root.visibleWindows[Math.min(root.selected, root.visibleWindows.length - 1)])
            Keys.onRightPressed: root.selected = Math.min(root.visibleWindows.length - 1, root.selected + 1)
            Keys.onLeftPressed: root.selected = Math.max(0, root.selected - 1)
            Keys.onDownPressed: root.selected = Math.min(root.visibleWindows.length - 1, root.selected + 3)
            Keys.onUpPressed: root.selected = Math.max(0, root.selected - 3)
            Keys.onDeletePressed: if (root.selectedAddress) root.requestClose(root.selectedAddress)
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Backspace) { root.query = root.query.slice(0, -1); root.selected = 0; event.accepted = true; }
                else if (event.modifiers === Qt.NoModifier && event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && root.query.length === 0) {
                    HyprlandService.switchToWorkspace(event.key - Qt.Key_0); root.hide(); event.accepted = true;
                } else if (event.text && event.text.length === 1 && event.text >= " " && !(event.modifiers & Qt.ControlModifier)) {
                    root.query += event.text; root.selected = 0; event.accepted = true;
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: Metrics.spaceLg

                // ── Header: mode + search ────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceMd
                    Text {
                        text: root.mode === "app" ? (root.activeClass || "Application") + " windows" : "Overview"
                        color: Colors.textPrimary
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeXxl
                        font.weight: Typography.weightSemibold
                    }
                    SegmentedControl {
                        options: [{ value: "all", label: "All" }, { value: "workspace", label: "This display" }, { value: "app", label: "This app" }]
                        current: root.mode
                        onSelected: function(v) { root.mode = v; root.selected = 0; }
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        Layout.preferredWidth: 300
                        Layout.preferredHeight: 36
                        radius: Metrics.radiusPill
                        color: Colors.withAlpha(Colors.surface, 0.85)
                        border.width: 1
                        border.color: root.query.length ? Colors.accent : Colors.border
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Metrics.spaceMd
                            anchors.rightMargin: Metrics.spaceMd
                            AetherIcon { width: 15; height: 15; name: "search"; color: Colors.textMuted }
                            Text {
                                Layout.fillWidth: true
                                text: root.query.length ? root.query : "Type to search windows"
                                color: root.query.length ? Colors.textPrimary : Colors.textMuted
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeMd
                                elide: Text.ElideRight
                            }
                            Text {
                                text: root.visibleWindows.length + " / " + root.flatWindows.length
                                color: Colors.textMuted
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeXs
                            }
                        }
                    }
                }

                // ── Workspaces (all / this display) ─────────────────
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.mode !== "app"
                    contentHeight: groupsColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: groupsColumn
                        width: parent.width
                        spacing: Metrics.spaceXl

                        Repeater {
                            model: root.groups
                            delegate: Column {
                                id: group
                                required property var modelData
                                required property int index
                                width: groupsColumn.width
                                spacing: Metrics.spaceSm

                                SectionLabel { text: group.modelData.monitor + (group.modelData.focused ? "  ·  focused" : "") }

                                Flow {
                                    width: parent.width
                                    spacing: Metrics.spaceLg
                                    readonly property real cardW: Math.min(420, Math.max(220, (width - spacing * 3) / 4))
                                    readonly property real cardH: cardW * group.modelData.geo.h / Math.max(1, group.modelData.geo.w)

                                    Repeater {
                                        model: group.modelData.workspaces
                                        delegate: WorkspaceCard {
                                            required property var modelData
                                            required property int index
                                            ws: modelData
                                            geo: group.modelData.geo
                                            width: parent.cardW
                                            height: parent.cardH + 30
                                            cardIndex: index + group.index * 4
                                        }
                                    }
                                    // "New workspace" drop target.
                                    NewWorkspaceCard { width: parent.cardW; height: parent.cardH + 30 }
                                }
                            }
                        }
                    }
                }

                // ── Exposé (this app) ───────────────────────────────
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.mode === "app"
                    columns: Math.max(1, Math.ceil(Math.sqrt(root.visibleWindows.length)))
                    rowSpacing: Metrics.spaceLg
                    columnSpacing: Metrics.spaceLg
                    Repeater {
                        model: root.mode === "app" ? root.visibleWindows : []
                        delegate: WindowTile {
                            required property var modelData
                            required property int index
                            client: modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.maximumHeight: 420
                            tileIndex: index
                            large: true
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: !HyprlandService.available
                    text: "Hyprland is not running — the overview needs its window data."
                    color: Colors.textMuted
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeMd
                }
            }
        }
    }

    // ── Pieces ─────────────────────────────────────────────────────────
    component WorkspaceCard: Item {
        id: card
        property var ws
        property var geo
        property int cardIndex: 0
        readonly property bool isDrop: root.dropTarget === ws.id && root.dragAddress.length > 0

        MotionCard {
            id: frame
            anchors.fill: parent
            index: card.cardIndex
            shown: root.open
            selected: card.ws.active || card.isDrop
            radius: Metrics.radiusLg
            fill: Colors.withAlpha(Colors.surface, card.isDrop ? 0.95 : 0.6)
            onClicked: { HyprlandService.switchToWorkspace(card.ws.id); root.hide(); }

            Item {
                id: screenArea
                x: Metrics.spaceSm; y: 28
                width: parent.width - Metrics.spaceSm * 2
                height: parent.height - 28 - Metrics.spaceSm
                readonly property real sx: width / Math.max(1, card.geo.w)
                readonly property real sy: height / Math.max(1, card.geo.h)

                Rectangle { anchors.fill: parent; radius: Metrics.radiusSm; color: Colors.withAlpha(Colors.bg0, 0.6) }

                Repeater {
                    model: card.ws.windows
                    delegate: WindowTile {
                        required property var modelData
                        client: modelData
                        x: Math.max(0, (modelData.at[0] - card.geo.x) * screenArea.sx)
                        y: Math.max(0, (modelData.at[1] - card.geo.y) * screenArea.sy)
                        width: Math.max(18, Math.min(screenArea.width - x, modelData.size[0] * screenArea.sx))
                        height: Math.max(14, Math.min(screenArea.height - y, modelData.size[1] * screenArea.sy))
                        z: modelData.floating ? 2 : 1
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: card.ws.windows.length === 0
                    text: "Empty"
                    color: Colors.textMuted
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeSm
                }
            }

            // Title (double-click to rename).
            Item {
                x: Metrics.spaceMd; y: 4
                width: parent.width - Metrics.spaceMd * 2; height: 22
                AetherIcon {
                    id: wsIcon
                    visible: card.ws.icon.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: 13; height: 13; name: card.ws.icon
                    color: card.ws.active ? Colors.accent : Colors.textSecondary
                }
                Text {
                    id: title
                    anchors.left: wsIcon.visible ? wsIcon.right : parent.left
                    anchors.leftMargin: wsIcon.visible ? 6 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !nameEdit.visible
                    text: (card.ws.name !== String(card.ws.id) ? card.ws.id + " · " + card.ws.name : "Workspace " + card.ws.id)
                    color: card.ws.active ? Colors.accent : Colors.textSecondary
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeSm
                    font.weight: Typography.weightSemibold
                    MouseArea { anchors.fill: parent; onDoubleClicked: { nameEdit.text = card.ws.name; nameEdit.visible = true; nameEdit.forceActiveFocus(); } }
                }
                TextInput {
                    id: nameEdit
                    visible: false
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    color: Colors.textPrimary
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeSm
                    maximumLength: 32
                    onAccepted: { root.rename(card.ws.id, text); visible = false; stage.forceActiveFocus(); }
                    Keys.onEscapePressed: { visible = false; stage.forceActiveFocus(); }
                }
            }
        }

        DropArea {
            anchors.fill: parent
            keys: ["aether-window"]
            onEntered: root.dropTarget = card.ws.id
            onExited: if (root.dropTarget === card.ws.id) root.dropTarget = -1
            onDropped: root.drop(root.dragAddress, card.ws.id)
        }
    }

    component NewWorkspaceCard: Item {
        id: nw
        readonly property bool isDrop: root.dropTarget === 0 && root.dragAddress.length > 0
        MotionCard {
            anchors.fill: parent
            shown: root.open
            selected: nw.isDrop
            fill: Colors.withAlpha(Colors.surface, nw.isDrop ? 0.9 : 0.3)
            onClicked: { const n = root.nextFreeWorkspace(); if (n > 0) { HyprlandService.switchToWorkspace(n); root.hide(); } }
            Column {
                anchors.centerIn: parent
                spacing: Metrics.spaceXs
                AetherIcon { anchors.horizontalCenter: parent.horizontalCenter; width: 22; height: 22; name: "plus"; color: Colors.textSecondary }
                Text {
                    text: root.dragAddress.length ? "Drop to move here" : "New workspace"
                    color: Colors.textSecondary
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeSm
                }
            }
        }
        DropArea {
            anchors.fill: parent
            keys: ["aether-window"]
            onEntered: root.dropTarget = 0
            onExited: if (root.dropTarget === 0) root.dropTarget = -1
            onDropped: root.drop(root.dragAddress, 0)
        }
    }

    component WindowTile: Item {
        id: tile
        property var client
        property int tileIndex: 0
        property bool large: false
        readonly property bool isSelected: root.selectedAddress === client.address
        readonly property bool dimmed: !root.matches(client)
        readonly property bool armed: root.armedClose === client.address

        opacity: dimmed ? 0.25 : 1
        Behavior on opacity { enabled: Motion.animate; NumberAnimation { duration: Motion.fast } }

        SpringValue { id: hoverLift; preset: "snappy"; target: (tileMouse.containsMouse || tile.isSelected) && !tile.dimmed ? 1 : 0 }

        Rectangle {
            id: body
            anchors.fill: parent
            radius: Math.min(Metrics.radiusSm, height / 4)
            color: Colors.withAlpha(Colors.surface, 0.95)
            border.width: tile.isSelected || tileMouse.containsMouse ? 1.5 : 1
            border.color: tile.armed ? Colors.danger : (tile.isSelected || tileMouse.containsMouse ? Colors.accent : Colors.border)
            scale: 1 + 0.03 * hoverLift.value
            clip: true

            Loader {
                id: preview
                anchors.fill: parent
                anchors.margins: 1
                active: Config.overview.thumbnails && root.open && tile.width > 60 && !Effects.eco
                source: "WindowPreview.qml"
                onLoaded: { item.address = Qt.binding(function() { return tile.client.address; }); }
            }

            Column {
                anchors.centerIn: parent
                spacing: 2
                visible: !(preview.status === Loader.Ready && preview.item && preview.item.ready)
                AppIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(48, tile.height * 0.45); height: width
                    iconName: (tile.client.class || "").toLowerCase()
                }
                Text {
                    visible: tile.height > 50
                    width: Math.min(tile.width - 8, implicitWidth)
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tile.client.title
                    color: Colors.textSecondary
                    font.family: Typography.family
                    font.pixelSize: tile.large ? Typography.sizeMd : Typography.sizeXs
                    elide: Text.ElideRight
                }
            }

            // Close button (click twice).
            Rectangle {
                visible: (tileMouse.containsMouse || tile.armed) && tile.width > 50
                anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 4
                width: 20; height: 20; radius: 10
                color: tile.armed ? Colors.danger : Colors.withAlpha(Colors.bg0, 0.8)
                AetherIcon { anchors.centerIn: parent; width: 10; height: 10; name: "close"; color: tile.armed ? Colors.onAccent : Colors.textPrimary }
                MouseArea { anchors.fill: parent; onClicked: root.requestClose(tile.client.address) }
                z: 3
            }
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            drag.target: dragProxy
            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            onClicked: function(mouse) {
                if (mouse.button === Qt.MiddleButton) root.requestClose(tile.client.address);
                else root.activate(tile.client);
            }
            onPressed: { dragProxy.x = 0; dragProxy.y = 0; }
            drag.onActiveChanged: {
                if (drag.active) { root.dragAddress = tile.client.address; dragProxy.Drag.active = true; }
                else { dragProxy.Drag.drop(); dragProxy.Drag.active = false; root.dragAddress = ""; root.dropTarget = -1; dragProxy.x = 0; dragProxy.y = 0; }
            }
        }

        // What actually moves while dragging (the tile stays in place).
        Rectangle {
            id: dragProxy
            width: tile.width; height: tile.height
            visible: Drag.active
            radius: body.radius
            color: Colors.withAlpha(Colors.accent, 0.35)
            border.width: 1.5
            border.color: Colors.accent
            Drag.keys: ["aether-window"]
            Drag.hotSpot.x: width / 2
            Drag.hotSpot.y: height / 2
            z: 100
        }
    }
}
