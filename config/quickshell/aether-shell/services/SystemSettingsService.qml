pragma Singleton
import QtQuick
import Quickshell
import "../core"

// Applies settings that live outside the shell, through the backend:
//   input.*              → `aether input apply` (input.conf + live hyprctl)
//   workspaces.appRules  → `aether workspace rules` (apprules.conf, version-aware)
//   power.autoSaver      → switches the power profile at the battery threshold
// Each is debounced so a slider drag applies once, and reports errors
// (e.g. an unknown keyboard layout) instead of writing a broken file.
Singleton {
    id: root

    property string inputError: ""
    property string rulesError: ""
    property bool _ready: false

    readonly property string _inputKey: JSON.stringify(Config.input)
    readonly property string _rulesKey: JSON.stringify(Config.workspaces.appRules)
    on_InputKeyChanged: if (root._ready) inputTimer.restart()
    on_RulesKeyChanged: if (root._ready) rulesTimer.restart()

    Timer {
        id: inputTimer; interval: 700
        onTriggered: CliService.run("input-apply", ["input", "apply", "--json"], function(ok, d, e) {
            root.inputError = ok ? "" : (d && d.problems ? d.problems.join("; ") : e);
        })
    }
    Timer {
        id: rulesTimer; interval: 700
        onTriggered: CliService.run("ws-rules", ["workspace", "rules", "--json"], function(ok, d, e) {
            root.rulesError = ok ? "" : (d && d.problems ? d.problems.join("; ") : e);
        })
    }
    Connections {
        target: Config
        function onReadyChanged() { if (Config.ready) root._ready = true; }
    }

    // Automatic power saver (opt-in): once per discharge, at the threshold.
    property bool _savedApplied: false
    property string _profileBefore: ""
    Connections {
        target: PowerService
        function onPercentageChanged() {
            if (!Config.power.autoSaver || !PowerService.available || PowerService.charging) return;
            if (!root._savedApplied && PowerService.percentage <= Config.power.autoSaverThreshold
                    && PowerProfileService.available && PowerProfileService.has("power-saver") && !PowerProfileService.batterySaver) {
                root._profileBefore = PowerProfileService.active || "";
                PowerProfileService.set("power-saver");
                root._savedApplied = true;
                EventBus.islandEvent("battery", { text: "Power saver on", level: PowerService.percentage, charging: false });
            }
        }
        function onChargingChanged() {
            // Restore the previous profile when plugged in again.
            if (PowerService.charging && root._savedApplied) {
                if (root._profileBefore && PowerProfileService.has(root._profileBefore)) PowerProfileService.set(root._profileBefore);
                root._savedApplied = false;
            }
        }
    }
}
