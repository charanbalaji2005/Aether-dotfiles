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

// The AetherOS dock (Settings → Dock; SUPER+Z shows/hides it).
//
// Items: favourite apps (shared with the launcher), then running apps that
// aren't favourites, then Downloads and (optionally) Trash.
//   click            focus the app's latest window; again cycles windows;
//                    launch it if it isn't running (with a bounce)
//   middle-click     open a new window
//   right-click      menu: pin/unpin, new window, its windows, close all
//   drag a favourite to reorder it
// Magnification follows the pointer along the dock with a Gaussian falloff;
// the pointer position itself rides a spring, so entering and leaving the
// dock eases instead of snapping. With auto-hide, the dock is a 3 px
// reveal strip until the pointer touches it.
Scope {
    id: root

    readonly property bool enabled: Config.dock.enabled
    readonly property string pos: Config.dock.position || "bottom"
    readonly property bool vertical: pos === "left" || pos === "right"
    readonly property int icon: Metrics.s(Config.dock.iconSize)
    readonly property real mag: Math.max(1, Config.dock.magnification)
    readonly property int pad: Metrics.spaceSm
    readonly property int thickness: icon + pad * 2 + 8

    property bool hovered: false
    property bool menuOpen: false
    readonly property bool revealed: !Config.dock.autoHide || hovered || menuOpen || dragging
        || (WindowService.available && HyprlandService.focusedWorkspace && WindowService.windowsOn(HyprlandService.focusedWorkspace.id).length === 0)
    property bool dragging: false

    // ── Items ─────────────────────────────────────────────────────────
    readonly property var favoriteApps: ApplicationService.favorites()
    readonly property var items: {
        const out = [];
        const favIds = {};
        for (const a of root.favoriteApps) { favIds[a.id] = true; out.push({ kind: "app", app: a, favorite: true, cls: "" }); }
        if (Config.dock.showRunning) {
            const seen = {};
            for (const cls of WindowService.runningClasses) {
                const a = ApplicationService.forClass(cls);
                const key = a ? a.id : "class:" + cls;
                if (seen[key] || (a && favIds[a.id])) continue;
                seen[key] = true;
                out.push({ kind: "app", app: a, favorite: false, cls: cls });
            }
        }
        if (Config.dock.showRecent) {
            const have = {};
            for (const it of out) if (it.app) have[it.app.id] = true;
            const recent = ApplicationService.recents().filter(function(a) { return !have[a.id]; }).slice(0, 3);
            if (recent.length) {
                out.push({ kind: "sep" });
                for (const a of recent) out.push({ kind: "app", app: a, favorite: false, cls: "", recent: true });
            }
        }
        out.push({ kind: "sep" });
        out.push({ kind: "folder", id: "downloads", label: "Downloads", icon: "folder-download" });
        if (Config.dock.showTrash) out.push({ kind: "folder", id: "trash", label: "Trash", icon: "user-trash" });
        return out;
    }

    function windowsFor(item) {
        if (item.kind !== "app") return [];
        if (!item.app) return WindowService.windowsOfClass(item.cls);
        return WindowService.clients.filter(function(c) { return ApplicationService.classMatches(item.app, c.class); });
    }

    function activate(item, newInstance) {
        if (item.kind === "folder") {
            const home = Quickshell.env("HOME");
            Quickshell.execDetached(["xdg-open", item.id === "trash" ? "trash:///" : (home + "/Downloads")]);
            return false;
        }
        const wins = root.windowsFor(item).sort(function(a, b) { return a.focusHistoryID - b.focusHistoryID; });
        if (!newInstance && wins.length > 0) {
            // Already focused → cycle to its next window.
            const target = wins[0].address === WindowService.activeAddress && wins.length > 1 ? wins[wins.length - 1] : wins[0];
            WindowService.focus(target.address);
            return false;
        }
        if (item.app) { ApplicationService.launch(item.app); return true; }
        return false;
    }

    function moveFavorite(fromId, toIndex) {
        const favs = (Config.launcher.favorites || []).slice();
        const i = favs.indexOf(fromId);
        if (i < 0) return;
        favs.splice(i, 1);
        favs.splice(Math.max(0, Math.min(favs.length, toIndex)), 0, fromId);
        Config.launcher.favorites = favs;
    }

    Connections {
        target: EventBus
        function onDockToggleRequested() { Config.dock.enabled = !Config.dock.enabled; }
    }
    IpcHandler {
        target: "dock"
        function toggle(): void { Config.dock.enabled = !Config.dock.enabled; }
        function show(): void { Config.dock.enabled = true; }
    }

    SpringValue { id: slide; preset: "smooth"; target: root.revealed ? 1 : 0 }

    PanelWindow {
        id: win
        visible: root.enabled
        screen: ShellState.activeScreen ? ShellState.activeScreen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
        WlrLayershell.namespace: "aether-dock"
        WlrLayershell.layer: WlrLayer.Top
        anchors {
            bottom: root.pos === "bottom"; left: root.pos === "left" || !root.vertical; right: root.pos === "right" || !root.vertical
            top: root.vertical
        }
        implicitHeight: root.vertical ? 0 : root.thickness * root.mag + 70
        implicitWidth: root.vertical ? root.thickness * root.mag + 70 : 0
        exclusiveZone: Config.dock.autoHide ? 0 : root.thickness + Metrics.spaceSm
        color: "transparent"
        // Input only on the dock body (or the reveal strip while hidden) and an open menu.
        mask: Region {
            item: root.revealed ? body : strip
            Region { item: menu.visible ? menu : null }
        }

        Item {
            id: strip
            width: root.vertical ? 3 : body.width
            height: root.vertical ? body.height : 3
            x: root.pos === "right" ? parent.width - 3 : root.pos === "left" ? 0 : body.x
            y: root.pos === "bottom" ? parent.height - 3 : body.y
            HoverHandler { onHoveredChanged: if (hovered) root.hovered = true }
        }

        Item {
            id: body
            readonly property real len: list.contentLength + root.pad * 2
            width: root.vertical ? root.thickness : len
            height: root.vertical ? len : root.thickness
            x: root.vertical ? (root.pos === "left" ? Metrics.spaceSm - (1 - slide.value) * (root.thickness + 12) : parent.width - width - Metrics.spaceSm + (1 - slide.value) * (root.thickness + 12))
                             : (parent.width - width) / 2
            y: root.vertical ? (parent.height - height) / 2
                             : parent.height - height - Metrics.spaceSm + (1 - slide.value) * (root.thickness + 12)
            opacity: 0.2 + 0.8 * slide.value

            HoverHandler {
                id: dockHover
                onHoveredChanged: {
                    if (hovered) { leave.stop(); root.hovered = true; }
                    else leave.restart();
                }
            }
            Timer { id: leave; interval: 500; onTriggered: if (!dockHover.hovered && !root.menuOpen) root.hovered = false }

            GlassPanel {
                anchors.fill: parent
                radius: Metrics.radiusXl
                tintOpacity: Config.dock.opacity
                elevation: 3
            }

            // Pointer coordinate along the dock, eased; -1e4 = away.
            SpringValue { id: pointer; preset: "fluid"; target: -10000 }
            Connections {
                target: dockHover
                function onPointChanged() {
                    if (!dockHover.hovered) return;
                    const p = dockHover.point.position;
                    const along = root.vertical ? p.y : p.x;
                    if (pointer.value < -5000) pointer.snap(along);
                    pointer.target = along;
                }
                function onHoveredChanged() { if (!dockHover.hovered) pointer.target = -10000; }
            }

            Item {
                id: list
                anchors.fill: parent
                anchors.margins: root.pad
                // Positions are computed rather than laid out, so magnified
                // neighbours push each other apart smoothly.
                readonly property var sizes: {
                    const out = [];
                    let along = 0;
                    const sigma = root.icon * 1.25;
                    for (let i = 0; i < root.items.length; i++) {
                        const base = root.items[i].kind === "sep" ? 10 : root.icon;
                        const centre = along + base / 2 + root.pad;
                        const d = pointer.value - centre;
                        const k = root.items[i].kind === "sep" || root.mag <= 1.001 || Effects.eco ? 1
                            : 1 + (root.mag - 1) * Math.exp(-(d * d) / (2 * sigma * sigma));
                        out.push(base * k);
                        along += base + 6;
                    }
                    return out;
                }
                readonly property real contentLength: {
                    let s = 0;
                    for (const v of sizes) s += v + 6;
                    return Math.max(0, s - 6);
                }

                Repeater {
                    model: root.items
                    delegate: DockItem {
                        required property var modelData
                        required property int index
                        item: modelData
                        itemIndex: index
                        size: list.sizes[index] || root.icon
                        offset: {
                            let s = 0;
                            for (let i = 0; i < index; i++) s += (list.sizes[i] || root.icon) + 6;
                            return s;
                        }
                    }
                }
            }
        }

        // ── Context menu ──────────────────────────────────────────────
        GlassPanel {
            id: menu
            visible: root.menuOpen && menuItem !== null
            property var menuItem: null
            property point anchor: Qt.point(0, 0)
            width: Config.dock.previews ? 300 : 230
            height: menuCol.implicitHeight + Metrics.spaceSm * 2
            radius: Metrics.radiusMd
            x: Math.max(4, Math.min(parent.width - width - 4, root.vertical ? (root.pos === "left" ? body.x + body.width + 8 : body.x - width - 8) : anchor.x - width / 2))
            y: Math.max(4, root.vertical ? anchor.y - height / 2 : body.y - height - 8)
            elevation: 3

            ColumnLayout {
                id: menuCol
                anchors.fill: parent
                anchors.margins: Metrics.spaceSm
                spacing: 2
                Text {
                    Layout.fillWidth: true; Layout.margins: 6
                    text: menu.menuItem ? (menu.menuItem.app ? menu.menuItem.app.name : (menu.menuItem.cls || menu.menuItem.label)) : ""
                    color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeMd; font.weight: Typography.weightSemibold
                    elide: Text.ElideRight
                }
                // Window previews (live thumbnail where Quickshell supports
                // screencopy; otherwise the title row alone).
                Flow {
                    Layout.fillWidth: true
                    visible: Config.dock.previews && menu.menuItem && root.windowsFor(menu.menuItem).length > 0
                    spacing: 6
                    Repeater {
                        model: menu.menuItem && Config.dock.previews ? root.windowsFor(menu.menuItem).slice(0, 4) : []
                        delegate: Rectangle {
                            required property var modelData
                            width: (menuCol.width - 6) / 2; height: width * 0.62
                            radius: Metrics.radiusSm
                            color: Colors.withAlpha(Colors.bg0, 0.6)
                            border.width: pa.containsMouse ? 1.5 : 1
                            border.color: pa.containsMouse ? Colors.accent : Colors.border
                            clip: true
                            Loader {
                                id: pv
                                anchors.fill: parent; anchors.margins: 1
                                active: root.menuOpen && !Effects.eco
                                source: "../overview/WindowPreview.qml"
                                onLoaded: item.address = Qt.binding(function() { return modelData.address; })
                            }
                            Text {
                                anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 4
                                text: modelData.title || modelData.class
                                elide: Text.ElideRight
                                color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeXs
                                style: Text.Outline; styleColor: Colors.withAlpha(Colors.bg0, 0.8)
                            }
                            MouseArea { id: pa; anchors.fill: parent; hoverEnabled: true; onClicked: { WindowService.focus(modelData.address); root.menuOpen = false; } }
                        }
                    }
                }
                Repeater {
                    model: menu.menuItem && !Config.dock.previews ? root.windowsFor(menu.menuItem) : []
                    delegate: MenuRow {
                        required property var modelData
                        label: modelData.title || modelData.class
                        iconName: "display"
                        onActivated: { WindowService.focus(modelData.address); root.menuOpen = false; }
                    }
                }
                MenuRow {
                    visible: menu.menuItem && menu.menuItem.app
                    label: "New window"; iconName: "plus"
                    onActivated: { root.activate(menu.menuItem, true); root.menuOpen = false; }
                }
                MenuRow {
                    visible: menu.menuItem && menu.menuItem.app
                    label: menu.menuItem && menu.menuItem.favorite ? "Unpin from dock" : "Pin to dock"
                    iconName: "star"
                    onActivated: { ApplicationService.toggleFavorite(menu.menuItem.app); root.menuOpen = false; }
                }
                MenuRow {
                    property bool armed: false
                    visible: menu.menuItem && root.windowsFor(menu.menuItem).length > 0
                    label: armed ? "Click again to close all" : "Close all windows"
                    iconName: "close"; danger: armed
                    onActivated: {
                        if (!armed) { armed = true; return; }
                        for (const w of root.windowsFor(menu.menuItem)) WindowService.close(w.address);
                        armed = false; root.menuOpen = false;
                    }
                }
            }
        }
    }

    component MenuRow: Rectangle {
        id: mr
        property string label
        property string iconName
        property bool danger: false
        signal activated()
        Layout.fillWidth: true
        implicitHeight: 30
        radius: Metrics.radiusSm
        color: mra.containsMouse ? (danger ? Colors.withAlpha(Colors.danger, 0.25) : Colors.surfaceHover) : "transparent"
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
            spacing: Metrics.spaceSm
            AetherIcon { width: 13; height: 13; name: mr.iconName; color: mr.danger ? Colors.danger : Colors.textSecondary }
            Text { Layout.fillWidth: true; text: mr.label; color: mr.danger ? Colors.danger : Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; elide: Text.ElideRight }
        }
        MouseArea { id: mra; anchors.fill: parent; hoverEnabled: true; onClicked: mr.activated() }
    }

    component DockItem: Item {
        id: di
        property var item
        property int itemIndex
        property real size
        property real offset
        readonly property var wins: root.windowsFor(item)
        readonly property bool active: wins.some(function(w) { return w.address === WindowService.activeAddress; })

        x: root.vertical ? (list.width - size) / 2 + (root.pos === "left" ? -(size - root.icon) / 2 : (size - root.icon) / 2) * 0 : offset
        y: root.vertical ? offset : list.height - size
        width: size
        height: size

        // Launch bounce: an upward impulse that a bouncy spring returns.
        SpringValue { id: bounce; preset: "bouncy"; target: 0 }

        Rectangle {
            visible: di.item.kind === "sep"
            anchors.centerIn: parent
            width: root.vertical ? root.icon * 0.7 : 1.5
            height: root.vertical ? 1.5 : root.icon * 0.7
            color: Colors.withAlpha(Colors.textMuted, 0.4)
        }

        Item {
            id: iconBox
            visible: di.item.kind !== "sep"
            width: di.size; height: di.size
            transform: Translate {
                x: root.vertical ? (root.pos === "left" ? 1 : -1) * bounce.value : 0
                y: root.vertical ? 0 : -bounce.value
            }
            AppIcon {
                anchors.fill: parent
                anchors.margins: di.size * 0.06
                iconName: di.item.kind === "folder" ? di.item.icon : (di.item.app ? di.item.app.icon : (di.item.cls || "").toLowerCase())
            }
            // Pressed dim.
            Rectangle { anchors.fill: parent; radius: Metrics.radiusMd; color: "black"; opacity: ma.pressed ? 0.18 : 0 }
        }

        // Running indicator: one dot per window (max 3), accent when active.
        Row {
            visible: di.wins.length > 0
            spacing: 3
            anchors.horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
            anchors.verticalCenter: root.vertical ? parent.verticalCenter : undefined
            anchors.top: root.vertical ? undefined : parent.bottom
            anchors.topMargin: 2
            x: root.vertical ? (root.pos === "left" ? -6 : parent.width + 2) : 0
            Repeater {
                model: Math.min(3, di.wins.length)
                delegate: Rectangle {
                    width: di.active ? 10 : 4; height: 4; radius: 2
                    color: di.active ? Colors.accent : Colors.textSecondary
                    SpringBehavior on width { preset: "snappy" }
                }
            }
        }

        // Tooltip.
        Rectangle {
            visible: ma.containsMouse && !root.menuOpen && !root.dragging && di.item.kind !== "sep"
            color: Colors.withAlpha(Colors.bg1, 0.95)
            radius: Metrics.radiusSm
            border.width: 1; border.color: Colors.border
            width: tip.implicitWidth + 14; height: tip.implicitHeight + 8
            x: root.vertical ? (root.pos === "left" ? di.width + 10 : -width - 10) : (di.width - width) / 2
            y: root.vertical ? (di.height - height) / 2 : -height - 10
            Text { id: tip; anchors.centerIn: parent; text: di.item.kind === "folder" ? di.item.label : (di.item.app ? di.item.app.name : di.item.cls); color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            enabled: di.item.kind !== "sep"
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            drag.target: di.item.favorite ? ghost : null
            drag.axis: root.vertical ? Drag.YAxis : Drag.XAxis
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    menu.menuItem = di.item;
                    const p = di.mapToItem(win.contentItem, di.width / 2, di.height / 2);
                    menu.anchor = Qt.point(p.x, p.y);
                    root.menuOpen = true;
                    return;
                }
                root.menuOpen = false;
                if (root.activate(di.item, mouse.button === Qt.MiddleButton) && Motion.animate) bounce.impulse(420);
            }
            drag.onActiveChanged: {
                root.dragging = drag.active;
                if (!drag.active && di.item.favorite && di.item.app) {
                    // New slot = position of the ghost centre among favourite slots.
                    const along = (root.vertical ? ghost.y : ghost.x) + di.offset + di.size / 2;
                    const step = root.icon + 6;
                    root.moveFavorite(di.item.app.id, Math.floor(along / step));
                    ghost.x = 0; ghost.y = 0;
                }
            }
        }
        Item { id: ghost; width: 1; height: 1 }
    }

    // Close the menu when clicking elsewhere on the desktop.
    Connections {
        target: EventBus
        function onClosePopups(except) { root.menuOpen = false; }
    }
}
