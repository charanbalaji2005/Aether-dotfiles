pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"
import "../automation/Rules.js" as Rules
import "../theme/Palettes.js" as Palettes

// Runs the user's automation rules (Settings → Automation).
//
// Events come from the existing services — nothing new is polled. The
// only timer is a once-a-minute tick, and only while a time-based rule is
// enabled. Every action goes through a fixed allowlist (Rules.ACTIONS).
//
// Safety:
//   * master switch Config.automation.enabled; off in safe mode
//   * a rule can't fire again within 3 s (debounce)
//   * a circuit breaker: more than 20 actions in a minute disables
//     automation and says so (protects against rules feeding each other)
//   * actions that fire triggers (switch-workspace → workspace-active) are
//     run with re-entry suppressed, so a rule can't trigger itself
Singleton {
    id: root

    readonly property bool enabled: Config.automation.enabled && PerformanceService.automationAllowed
    readonly property var rules: (Config.automation.rules || []).filter(function(r) { return Rules.validate(r) === ""; })
    readonly property var invalidRules: (Config.automation.rules || []).filter(function(r) { return Rules.validate(r) !== ""; })
    property var history: []        // newest first: { time, rule, name, ok, detail }
    property bool _running: false
    property var _lastFired: ({})
    property var _recent: []
    property string breakerReason: ""

    function _log(rule, ok, detail) {
        const e = { time: Qt.formatDateTime(new Date(), "hh:mm:ss"), rule: rule.id, name: rule.name || Rules.describe(rule), ok: ok, detail: detail || "" };
        root.history = [e].concat(root.history).slice(0, 50);
        (ok ? Logger.info : Logger.warn)("AutomationService", e.name + ": " + (ok ? "ran" : "failed") + (detail ? " — " + detail : ""));
    }

    function _state() {
        return { onBattery: ShellState.onBattery, battery: PowerService.available ? PowerService.percentage : 100, now: new Date() };
    }

    // Entry point for every event.
    function fire(event) {
        if (!root.enabled || root._running) return;
        for (const rule of root.rules) {
            if (!rule.enabled || !Rules.matches(rule, event)) continue;
            if (!Rules.conditionsHold(rule, root._state())) continue;
            const now = Date.now();
            if (root._lastFired[rule.id] && now - root._lastFired[rule.id] < 3000) continue;
            root._lastFired[rule.id] = now;
            root._execute(rule);
        }
    }

    function _breaker() {
        const now = Date.now();
        root._recent = root._recent.filter(function(t) { return now - t < 60000; }).concat([now]);
        if (root._recent.length > 20) {
            Config.automation.enabled = false;
            root.breakerReason = "More than 20 automated actions ran within a minute; automation was switched off to stop a possible loop.";
            EventBus.notificationRequested("Automation paused", root.breakerReason, "critical");
            return false;
        }
        return true;
    }

    function _execute(rule) {
        if (!root._breaker()) return;
        root._running = true;
        const results = [];
        for (const a of Rules.actionsOf(rule)) {
            const r = root._runAction(a);
            results.push(r);
            if (!r.ok) break;          // later actions may depend on earlier ones
        }
        const failed = results.filter(function(r) { return !r.ok; });
        root._log(rule, failed.length === 0, failed.map(function(r) { return r.detail; }).join("; "));
        // Events caused by these actions arrive on later ticks; keep re-entry closed until then.
        reentry.restart();
    }

    function _runAction(a) {
        let ok = true, detail = "";
        try {
            switch (a.type) {
            case "set-quality": Config.effects.quality = a.value; break;
            case "set-theme-mode": Config.appearance.theme = a.value; break;
            case "set-motion": Config.general.motionProfile = a.value; break;
            case "set-palette":
                if (Palettes.palettes[a.value] !== undefined && a.value !== "aether-light") Config.appearance.palette = a.value;
                else { ok = false; detail = "unknown palette " + a.value; }
                break;
            case "set-profile": ProfileService.apply(a.value); break;
            case "apply-layout": LayoutService.apply(a.value, true); break;
            case "set-power-profile":
                if (PowerProfileService.available && PowerProfileService.has(a.value)) PowerProfileService.set(a.value);
                else { ok = false; detail = "power profile " + a.value + " is not available"; }
                break;
            case "set-wallpaper": WallpaperService.setWallpaper(a.value); break;
            case "next-wallpaper": WallpaperService.nextWallpaper(); break;
            case "launch-app": {
                // Desktop entries only: the rule names an app, never a command line.
                const app = ApplicationService.applications.find(function(x) {
                    return x.id === a.app || x.id === a.app + ".desktop" || x.id.toLowerCase() === a.app.toLowerCase() + ".desktop";
                });
                if (app) ApplicationService.launch(app); else { ok = false; detail = "no installed app " + a.app; }
                break;
            }
            case "switch-workspace": HyprlandService.switchToWorkspace(a.value); break;
            case "set-volume": if (AudioService.available) AudioService.setVolume(a.value / 100); else { ok = false; detail = "no audio output"; } break;
            case "set-dnd": Config.notifications.doNotDisturb = a.value; break;
            case "set-dock": Config.dock.enabled = a.value; break;
            case "notify": EventBus.notificationRequested(a.title, a.body || "", "normal"); break;
            default: ok = false; detail = "unsupported action " + a.type;
            }
        } catch (e) {
            ok = false; detail = String(e);
        }
        return { ok: ok, detail: detail };
    }
    Timer { id: reentry; interval: 400; onTriggered: root._running = false }

    // "Test" button: run the action now, ignoring trigger and conditions.
    function test(rule) {
        if (Rules.validate(rule) !== "") return Rules.validate(rule);
        root._running = false;
        root._execute(rule);
        return "";
    }

    // ── Event sources ─────────────────────────────────────────────────
    Connections {
        target: ShellState
        function onOnBatteryChanged() { root.fire({ type: ShellState.onBattery ? "power-disconnected" : "power-connected" }); }
    }

    property real _lastBattery: PowerService.percentage
    Connections {
        target: PowerService
        function onPercentageChanged() {
            root.fire({ type: "battery-below", value: PowerService.percentage, previous: root._lastBattery });
            root._lastBattery = PowerService.percentage;
        }
    }

    Connections {
        target: WindowService
        function onWindowOpened(cls, title, address) { root.fire({ type: "app-opened", app: cls }); }
        function onWindowClosed(cls, address) { root.fire({ type: "app-closed", app: cls }); }
    }

    readonly property int _workspace: HyprlandService.focusedWorkspace ? HyprlandService.focusedWorkspace.id : -1
    on_WorkspaceChanged: if (_workspace > 0) root.fire({ type: "workspace-active", value: _workspace })

    property int _screens: Quickshell.screens.length
    Connections {
        target: Quickshell
        function onScreensChanged() {
            const n = Quickshell.screens.length;
            if (n > root._screens) root.fire({ type: "monitor-connected" });
            else if (n < root._screens) root.fire({ type: "monitor-disconnected" });
            root._screens = n;
        }
    }

    readonly property string _netKey: NetworkService.connected + "|" + NetworkService.connectionType + "|" + NetworkService.ssid
    on_NetKeyChanged: networkDebounce.restart()
    Timer { id: networkDebounce; interval: 1500; onTriggered: root.fire({ type: "network-changed" }) }

    // Bluetooth: diff the connected-device set.
    readonly property var _btConnected: {
        const d = BluetoothService.devices;
        const list = d && d.values ? d.values : [];
        return list.filter(function(x) { return x && x.connected; }).map(function(x) { return x.name || x.address || ""; });
    }
    property var _btPrev: []
    on_BtConnectedChanged: {
        const now = root._btConnected, prev = root._btPrev;
        for (const n of now) if (prev.indexOf(n) < 0) root.fire({ type: "bluetooth-connected", device: n });
        for (const n of prev) if (now.indexOf(n) < 0) root.fire({ type: "bluetooth-disconnected", device: n });
        root._btPrev = now;
    }

    // Startup: once per shell start, after settings are loaded.
    Timer { id: startupTick; interval: 3000; onTriggered: root.fire({ type: "startup" }) }
    Connections {
        target: Config
        function onReadyChanged() { if (Config.ready) startupTick.start(); }
    }
    Connections {
        target: ProfileService
        function onLastAppliedChanged() { if (ProfileService.lastApplied) root.fire({ type: "profile-applied", value: ProfileService.lastApplied }); }
    }

    Connections {
        target: TimerService
        function onFocusStarted() { root.fire({ type: "focus-started" }); }
        function onFocusEnded() { root.fire({ type: "focus-ended" }); }
    }

    // Time triggers: tick on the minute, only while such a rule exists.
    readonly property bool _hasTimeRules: root.enabled && root.rules.some(function(r) { return r.enabled && r.trigger.type === "time"; })
    Timer {
        id: minuteTick
        running: root._hasTimeRules
        repeat: true
        interval: 60000 - (new Date().getSeconds() * 1000)
        onTriggered: {
            interval = 60000;
            root.fire({ type: "time", at: Qt.formatTime(new Date(), "hh:mm") });
        }
    }

    // ── Rule editing helpers for Settings ─────────────────────────────
    function saveRule(rule) {
        const err = Rules.validate(rule);
        if (err) return err;
        const list = (Config.automation.rules || []).filter(function(r) { return r.id !== rule.id; });
        list.push(rule);
        Config.automation.rules = list;
        return "";
    }
    function deleteRule(id) {
        Config.automation.rules = (Config.automation.rules || []).filter(function(r) { return r.id !== id; });
    }
    function setEnabled(id, on) {
        Config.automation.rules = (Config.automation.rules || []).map(function(r) {
            return r.id === id ? Object.assign({}, r, { enabled: on }) : r;
        });
    }
    function newId() { return "r" + Date.now().toString(36); }
}
