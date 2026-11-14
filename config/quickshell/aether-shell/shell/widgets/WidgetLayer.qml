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

// Desktop widgets: a transparent layer below windows on each monitor.
// Each widget is loaded in its own Loader from its validated directory and
// receives a permission-filtered WidgetApi. A widget that fails to load (or
// whose files changed and no longer pass validation) shows an error card;
// the others are unaffected. In edit mode (SUPER+SHIFT+Y or Settings →
// Widgets) widgets can be dragged (snapping to the grid) and removed.
Scope {
    id: root

    Variants {
        model: Config.widgets.enabled ? Quickshell.screens : []
        delegate: Component {
            PanelWindow {
                id: win
                required property var modelData
                screen: modelData
                WlrLayershell.namespace: "aether-widgets"
                WlrLayershell.layer: WidgetService.editing ? WlrLayer.Top : WlrLayer.Bottom
                WlrLayershell.keyboardFocus: WidgetService.editing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
                exclusionMode: ExclusionMode.Ignore
                anchors { top: true; bottom: true; left: true; right: true }
                color: WidgetService.editing ? Colors.withAlpha(Colors.bg0, 0.35) : "transparent"
                // Only the widget cards (and the edit toolbar) take input, so
                // the empty desktop stays click-through and wallpaper parallax
                // keeps receiving the pointer. Regions are rebuilt when cards
                // change; old ones are destroyed.
                mask: Region { id: maskRegion }
                property var _regions: []
                function rebuildMask() {
                    for (const r of win._regions) r.destroy();
                    const rs = [];
                    for (let i = 0; i < cards.count; i++) {
                        const it = cards.itemAt(i);
                        if (it) rs.push(regionComponent.createObject(maskRegion, { item: it }));
                    }
                    if (WidgetService.editing) rs.push(regionComponent.createObject(maskRegion, { item: editBar }));
                    win._regions = rs;
                    maskRegion.regions = rs;
                }
                Component { id: regionComponent; Region {} }
                Connections {
                    target: WidgetService
                    function onEditingChanged() { win.rebuildMask(); }
                }

                readonly property var mine: (Config.widgets.placed || []).filter(function(p) { return !p.screen || p.screen === win.modelData.name; })

                Repeater {
                    id: cards
                    model: win.mine
                    onCountChanged: Qt.callLater(win.rebuildMask)
                    delegate: Item {
                        id: card
                        required property var modelData
                        readonly property var meta: WidgetService.info(modelData.widget)
                        x: modelData.x; y: modelData.y
                        width: modelData.w || (meta && meta.size ? meta.size.w : 240)
                        height: modelData.h || (meta && meta.size ? meta.size.h : 160)

                        GlassPanel { anchors.fill: parent; radius: Metrics.radiusLg; elevation: 2; focused: WidgetService.editing && drag.active }

                        // Built-ins always; third-party only when allowed, trusted
                            // at their current digest (backend decides: meta.loadable)
                            // and never in safe mode.
                        readonly property bool allowed: card.meta !== null && card.meta.loadable === true
                            && (card.meta.source === "builtin" || !PerformanceService.safeMode)
                        Loader {
                            id: loader
                            anchors.fill: parent
                            active: card.allowed
                            source: active ? "file://" + card.meta.path + "/" + card.meta.entry : ""
                            onLoaded: {
                                const api = apiComponent.createObject(item, { permissions: card.meta.permissions || [] });
                                if ("api" in item) item.api = api;
                            }
                            onStatusChanged: {
                                if (status === Loader.Error) Logger.warn("WidgetLayer", "Widget " + card.modelData.widget + " failed to load");
                                else if (status === Loader.Ready) Logger.info("WidgetLayer", "Widget " + card.modelData.widget + " (" + card.meta.source + ") activated");
                            }
                        }
                        Text {
                            anchors.centerIn: parent; width: parent.width - 20
                            visible: !card.allowed || loader.status === Loader.Error
                            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                            text: !card.meta ? "Widget “" + card.modelData.widget + "” is not installed"
                                : !card.meta.valid ? "Blocked: " + (card.meta.problems || []).slice(0, 2).join("; ")
                                : PerformanceService.safeMode && card.meta.source !== "builtin" ? "Third-party widgets are off in safe mode"
                                : !card.meta.loadable ? "Not loaded: " + card.meta.blockedReason
                                : "This widget failed to load (see aether logs --shell)"
                            color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
                        }

                        // Edit mode: drag to move, × to remove.
                        MouseArea {
                            id: drag
                            anchors.fill: parent
                            enabled: WidgetService.editing
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            property point start
                            property point origin
                            readonly property bool active: pressed
                            onPressed: function(m) { start = mapToItem(win.contentItem, m.x, m.y); origin = Qt.point(card.x, card.y); }
                            onPositionChanged: function(m) {
                                const p = mapToItem(win.contentItem, m.x, m.y);
                                card.x = Math.max(0, Math.min(win.width - card.width, origin.x + p.x - start.x));
                                card.y = Math.max(0, Math.min(win.height - card.height, origin.y + p.y - start.y));
                            }
                            onReleased: WidgetService.move(card.modelData.id, card.x, card.y)
                        }
                        Rectangle {
                            visible: WidgetService.editing
                            anchors.top: parent.top; anchors.right: parent.right; anchors.margins: -8
                            width: 24; height: 24; radius: 12; color: Colors.danger
                            AetherIcon { anchors.centerIn: parent; width: 10; height: 10; name: "close"; color: "white" }
                            MouseArea { anchors.fill: parent; onClicked: WidgetService.remove(card.modelData.id) }
                        }
                    }
                }

                // Edit-mode toolbar: add widgets, done.
                GlassPanel {
                    id: editBar
                    visible: WidgetService.editing
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 80
                    width: barRow.implicitWidth + 32; height: 52
                    radius: 26; elevation: 3
                    RowLayout {
                        id: barRow
                        anchors.centerIn: parent
                        spacing: Metrics.spaceSm
                        Text { text: "Add:"; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
                        ChipGroup {
                            options: WidgetService.catalog.filter(function(w) { return w.loadable; }).map(function(w) { return { value: w.id, label: w.name }; })
                            current: ""
                            onSelected: function(v) { WidgetService.place(v, win.modelData.name); }
                        }
                        ChipGroup { options: [{ value: "done", label: "Done" }]; current: "done"; onSelected: WidgetService.editing = false }
                    }
                }
            }
        }
    }

    Component { id: apiComponent; WidgetApi {} }

    Connections {
        target: EventBus
        function onWidgetEditRequested() {
            if (!Config.widgets.enabled) Config.widgets.enabled = true;
            WidgetService.refresh();
            WidgetService.editing = !WidgetService.editing;
        }
    }
    IpcHandler {
        target: "widgets"
        function edit(): void { EventBus.widgetEditRequested(); }
    }
}
