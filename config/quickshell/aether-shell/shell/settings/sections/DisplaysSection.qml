import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → Displays. Only modes the monitor reports can be chosen. A
// change is applied, then reverted automatically after 15 s unless you press
// Keep — by a separate watchdog process, so it reverts even if the shell
// can't draw anything on the new mode.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg
    property var monitors: []
    property string selected: ""
    property string pendingMode: ""
    property real pendingScale: 1
    property int countdown: 0
    property string message: ""

    function reload() {
        CliService.run("displays", ["display", "list", "--json"], function(ok, d, e) {
            root.monitors = ok ? d : [];
            root.message = ok ? "" : "Hyprland is not running.";
            if (ok && d.length && !d.some(function(m) { return m.name === root.selected; })) root.selected = d[0].name;
        });
    }
    Component.onCompleted: reload()
    readonly property var mon: monitors.find(function(m) { return m.name === root.selected; }) || null
    onMonChanged: if (mon) { pendingMode = mon.width + "x" + mon.height + "@" + mon.refresh.toFixed(2) + "Hz"; pendingScale = mon.scale; }

    Timer {
        id: tick; interval: 1000; repeat: true; running: root.countdown > 0
        onTriggered: { root.countdown -= 1; if (root.countdown === 0) { root.message = "Not confirmed — the previous configuration was restored."; root.reload(); } }
    }

    ChipGroup {
        visible: root.monitors.length > 1
        options: root.monitors.map(function(m) { return { value: m.name, label: m.name + " · " + (m.make || "") + " " + (m.model || "") }; })
        current: root.selected
        onSelected: function(v) { root.selected = v; }
    }
    Text {
        visible: root.mon !== null
        text: root.mon ? root.mon.description + (root.mon.focused ? "  ·  focused" : "") : ""
        color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm
    }
    SettingRow {
        visible: root.mon !== null
        label: "Resolution and refresh rate"
        ChipGroup {
            Layout.maximumWidth: 420
            options: root.mon ? root.mon.modes.slice(0, 14).map(function(m) { return { value: m, label: m.replace("@", " @ ").replace(/\.00Hz$/, " Hz").replace(/Hz$/, " Hz") }; }) : []
            current: root.pendingMode
            onSelected: function(v) { root.pendingMode = v; }
        }
    }
    SettingRow {
        visible: root.mon !== null
        label: "Scale"
        ChipGroup {
            options: [1, 1.25, 1.333333, 1.5, 1.6, 1.75, 2].map(function(s) { return { value: String(s), label: Math.round(s * 100) + "%" }; })
            current: String(root.pendingScale)
            onSelected: function(v) { root.pendingScale = parseFloat(v); }
        }
    }
    RowLayout {
        visible: root.mon !== null
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: root.countdown > 0 ? "Keep these settings? Reverting in " + root.countdown + " s." : root.message
            color: root.countdown > 0 ? Colors.warning : Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm
        }
        ChipGroup {
            visible: root.countdown > 0
            options: [{ value: "revert", label: "Revert now" }]; current: ""
            onSelected: CliService.run("display-revert", ["display", "revert", "--json"], function() { root.countdown = 0; root.message = "Reverted."; root.reload(); })
        }
        ChipGroup {
            visible: root.countdown > 0
            options: [{ value: "keep", label: "Keep" }]; current: "keep"
            onSelected: CliService.run("display-confirm", ["display", "confirm", "--json"], function(ok) { root.countdown = 0; root.message = ok ? "Saved." : "Too late: it was already reverted."; root.reload(); })
        }
        ChipGroup {
            visible: root.countdown === 0
            options: [{ value: "apply", label: "Apply" }]; current: "apply"
            onSelected: CliService.run("display-apply", ["display", "apply", root.selected, root.pendingMode, "--scale", String(root.pendingScale), "--confirm-within", "15", "--json"], function(ok, d, e) {
                if (ok && d.ok) { root.countdown = 15; root.message = ""; }
                else root.message = (d && d.problems ? d.problems.join("; ") : e);
            })
        }
    }
    SectionLabel { text: "Profiles"; Layout.topMargin: Metrics.spaceSm }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "Save the current arrangement for this set of monitors; it's re-applied automatically whenever the same monitors are connected (e.g. docking a laptop)."
        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
    }
    ChipGroup {
        options: [{ value: "save", label: "Save as profile for these monitors" }]; current: ""
        onSelected: CliService.run("display-profile", ["display", "save-profile", "set-" + root.monitors.length + "-" + Date.now().toString(36), "--json"], function(ok, d, e) { root.message = ok ? "Profile saved." : e; })
    }
    Text { visible: root.monitors.length === 0; text: root.message || "Loading…"; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
}
