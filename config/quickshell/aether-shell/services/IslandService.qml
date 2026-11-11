pragma Singleton
import QtQuick
import Quickshell
import "../core"

// What the Dynamic Island shows.
//
// Persistent "activities" are derived from real services (media playing,
// recording, a timer, focus session, charging). Transient "events" (charger
// plugged, recording saved, timer done, an important notification) are
// queued and shown one at a time for a few seconds, then the island returns
// to the highest-priority activity. Priorities are fixed and documented
// below; nothing is shown that its service doesn't actually report.
Singleton {
    id: root

    // Priority: privacy (mic/camera) > recording > timer/focus > media > charging.
    readonly property var activities: {
        const out = [];
        if (Config.island.showPrivacy && (PrivacyService.micInUse || PrivacyService.cameraInUse)) out.push("privacy");
        if (Config.island.showRecording && RecordingService.recording) out.push("recording");
        if (Config.island.showTimers && (TimerService.countdownRunning || TimerService.countdownPaused || TimerService.focusActive)) out.push("timer");
        if (Config.island.showTimers && TimerService.stopwatchRunning) out.push("stopwatch");
        if (Config.island.showMedia && MediaService.available) out.push("media");
        if (Config.island.showBattery && PowerService.available && PowerService.charging) out.push("charging");
        return out;
    }
    readonly property string primary: activities.length > 0 ? activities[0] : ""

    property var queue: []
    property var current: null      // { kind, payload }
    readonly property bool hasEvent: current !== null

    // Every event shown, newest first (Settings → Dock & island → history).
    property var history: []

    function push(kind, payload) {
        if (kind === "notification" && !Config.island.showNotifications) return;
        if (kind === "battery" && !Config.island.showBattery) return;
        if (kind === "network" && !Config.island.showNetwork) return;
        if (kind === "screenshot" && !Config.island.showScreenshots) return;
        if (kind === "clipboard" && !Config.island.showClipboard) return;
        const ev = { kind: kind, payload: payload || {}, time: Qt.formatTime(new Date(), "hh:mm") };
        root.history = [ev].concat(root.history).slice(0, 40);
        root.queue = root.queue.concat([ev]).slice(-6);
        if (!root.current) root._next();
    }

    // External posts (`aether island post`, `qs ipc call island post`):
    // plain text only, length-limited, at most 6 per minute so a runaway
    // script can't monopolise the island.
    property var _posts: []
    function post(title, body) {
        if (!Config.island.allowExternal) return false;
        const now = Date.now();
        root._posts = root._posts.filter(function(t) { return now - t < 60000; });
        if (root._posts.length >= 6) return false;
        root._posts = root._posts.concat([now]);
        const clean = function(x, n) { return String(x || "").replace(/[\u0000-\u001f]/g, " ").substring(0, n); };
        root.push("external", { text: clean(title, 80), body: clean(body, 200) });
        return true;
    }
    function dismiss() { root._next(); }
    function _next() {
        if (root.queue.length === 0) { root.current = null; eventTimer.stop(); return; }
        root.current = root.queue[0];
        root.queue = root.queue.slice(1);
        eventTimer.restart();
    }
    Timer { id: eventTimer; interval: Math.max(2, Config.island.eventSeconds) * 1000; onTriggered: root._next() }

    Connections {
        target: EventBus
        function onIslandEvent(kind, payload) { root.push(kind, payload); }
    }

    // Network: connected / disconnected / VPN up or down (debounced, so a
    // Wi-Fi roam doesn't produce three events).
    readonly property string _netState: NetworkService.connected ? (NetworkService.connectionType + ":" + NetworkService.ssid) : "offline"
    property string _netShown: ""
    on_NetStateChanged: netDebounce.restart()
    Timer {
        id: netDebounce; interval: 2500
        onTriggered: {
            if (root._netShown === "" ) { root._netShown = root._netState; return; }   // the state at startup isn't news
            if (root._netState === root._netShown) return;
            root._netShown = root._netState;
            root.push("network", { text: NetworkService.connected
                ? "Connected" + (NetworkService.ssid ? " to " + NetworkService.ssid : " (" + NetworkService.connectionType + ")")
                : "Disconnected", connected: NetworkService.connected });
        }
    }
    property var _vpnsShown: null
    Connections {
        target: NetworkService
        function onVpnsChanged() {
            if (root._vpnsShown === null) { root._vpnsShown = NetworkService.vpns; return; }
            const up = NetworkService.vpns.filter(function(v) { return root._vpnsShown.indexOf(v) < 0; });
            const down = root._vpnsShown.filter(function(v) { return NetworkService.vpns.indexOf(v) < 0; });
            for (const v of up) root.push("network", { text: "VPN connected: " + v, connected: true, vpn: true });
            for (const v of down) root.push("network", { text: "VPN disconnected: " + v, connected: false, vpn: true });
            root._vpnsShown = NetworkService.vpns;
        }
    }

    // Charger plugged/unplugged.
    Connections {
        target: ShellState
        function onOnBatteryChanged() {
            if (!PowerService.available) return;
            root.push("battery", { text: ShellState.onBattery ? "On battery" : "Charging", level: PowerService.percentage, charging: !ShellState.onBattery });
        }
    }
}
