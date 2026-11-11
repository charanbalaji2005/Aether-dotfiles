import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → Gestures. Screen edges are handled by the shell; touchpad
// swipes are compositor gestures, so changing them rewrites compat.conf
// (`aether hyprland compat`, debounced) — Hyprland reloads it by itself.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg

    readonly property var actionOptions: ActionService.actions.map(function(a) { return { value: a.id, label: a.label }; })
    property string status: ""
    readonly property string swipeKey: Config.gestures.workspaceSwipe + "|" + Config.gestures.swipeUp + "|" + Config.gestures.swipeDown
    property bool _ready: false
    Component.onCompleted: _ready = true
    onSwipeKeyChanged: if (_ready) regen.restart()
    Timer {
        id: regen; interval: 700
        onTriggered: CliService.run("compat", ["hyprland", "compat", "--json"], function(ok, d, e) { root.status = ok ? "Touchpad gestures updated." : "Couldn't update gestures: " + e; })
    }

    SectionLabel { text: "Touchpad (three fingers)" }
    SettingRow {
        label: "Swipe left/right switches workspaces"
        Switch { checked: Config.gestures.workspaceSwipe; onToggled: function(v) { Config.gestures.workspaceSwipe = v; } }
    }
    SettingRow {
        label: "Swipe up"
        ChipGroup { Layout.maximumWidth: 380; options: root.actionOptions.filter(function(o) { return o.value !== "wallpaper-next"; }); current: Config.gestures.swipeUp; onSelected: function(v) { Config.gestures.swipeUp = v; } }
    }
    SettingRow {
        label: "Swipe down"
        ChipGroup { Layout.maximumWidth: 380; options: root.actionOptions.filter(function(o) { return o.value !== "wallpaper-next"; }); current: Config.gestures.swipeDown; onSelected: function(v) { Config.gestures.swipeDown = v; } }
    }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: (root.status ? root.status + " " : "") + "Vertical swipes need Hyprland 0.51 or newer. Typing or dragging a window never triggers them (Hyprland disables gestures during those)."
        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
    }

    SectionLabel { text: "Screen edges (pointer)"; Layout.topMargin: Metrics.spaceSm }
    SettingRow {
        label: "Activate by resting at an edge"
        description: "Corners are excluded; nothing triggers while a fullscreen app is focused"
        Switch { checked: Config.gestures.edgesEnabled; onToggled: function(v) { Config.gestures.edgesEnabled = v; } }
    }
    Repeater {
        model: [{ key: "edgeLeft", label: "Left edge" }, { key: "edgeRight", label: "Right edge" }, { key: "edgeTop", label: "Top edge" }, { key: "edgeBottom", label: "Bottom edge" }]
        delegate: SettingRow {
            id: edgeRow
            required property var modelData
            visible: Config.gestures.edgesEnabled
            label: modelData.label
            ChipGroup { Layout.maximumWidth: 380; options: root.actionOptions; current: Config.gestures[edgeRow.modelData.key]; onSelected: function(v) { Config.gestures[edgeRow.modelData.key] = v; } }
        }
    }
    SettingRow {
        visible: Config.gestures.edgesEnabled
        label: "Rest time before it triggers"
        description: Config.gestures.edgeDwellMs + " ms"
        Slider { implicitWidth: 180; from: 0; to: 1000; value: Config.gestures.edgeDwellMs; format: function(v) { return Math.round(v) + " ms"; }; onMoved: function(v) { Config.gestures.edgeDwellMs = Math.round(v / 10) * 10; } }
    }
}
