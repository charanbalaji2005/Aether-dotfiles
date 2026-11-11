pragma Singleton
import QtQuick
import Quickshell
import "../core"

// Countdown timer, stopwatch and focus (Pomodoro) sessions.
//
// One 1 s Timer, running only while something is counting. Elapsed time is
// computed from wall-clock start times, not by counting ticks, so a
// suspended laptop or a stalled frame can't make a timer drift.
// Focus sessions can switch on Do Not Disturb for their duration (and put
// it back exactly as it was afterwards).
Singleton {
    id: root

    // ── Countdown ─────────────────────────────────────────────────────
    property int countdownTotal: 0        // seconds
    property real _countdownEnd: 0        // ms epoch; 0 = not running
    property int _countdownPausedLeft: 0
    readonly property bool countdownRunning: _countdownEnd > 0
    readonly property bool countdownPaused: _countdownPausedLeft > 0
    property int countdownLeft: 0

    function startCountdown(seconds) {
        if (!(seconds > 0)) return;
        root.countdownTotal = seconds;
        root._countdownPausedLeft = 0;
        root._countdownEnd = Date.now() + seconds * 1000;
        root._tick();
    }
    function pauseCountdown() {
        if (!root.countdownRunning) return;
        root._countdownPausedLeft = root.countdownLeft;
        root._countdownEnd = 0;
    }
    function resumeCountdown() {
        if (!root.countdownPaused) return;
        root._countdownEnd = Date.now() + root._countdownPausedLeft * 1000;
        root._countdownPausedLeft = 0;
    }
    function cancelCountdown() { root._countdownEnd = 0; root._countdownPausedLeft = 0; root.countdownLeft = 0; root.countdownTotal = 0; }

    // ── Stopwatch ─────────────────────────────────────────────────────
    property real _swStart: 0
    property real _swAccum: 0             // ms from earlier runs
    readonly property bool stopwatchRunning: _swStart > 0
    property real stopwatchMs: 0
    function startStopwatch() { if (!root.stopwatchRunning) root._swStart = Date.now(); }
    function pauseStopwatch() { if (root.stopwatchRunning) { root._swAccum += Date.now() - root._swStart; root._swStart = 0; root._tick(); } }
    function resetStopwatch() { root._swStart = 0; root._swAccum = 0; root.stopwatchMs = 0; }

    // ── Focus sessions (Pomodoro) ─────────────────────────────────────
    property int focusMinutes: 25
    property int breakMinutes: 5
    property bool focusDnd: true
    property string focusPhase: "idle"     // "idle" | "focus" | "break"
    property int focusRound: 0
    property real _phaseEnd: 0
    property int focusLeft: 0
    property bool _dndBefore: false
    readonly property bool focusActive: focusPhase !== "idle"

    signal focusStarted()
    signal focusEnded()

    function startFocus(minutes) {
        if (root.focusActive) return;
        if (minutes > 0) root.focusMinutes = minutes;
        root.focusRound = 1;
        root._enterPhase("focus");
        root._dndBefore = Config.notifications.doNotDisturb;
        if (root.focusDnd) Config.notifications.doNotDisturb = true;
        root.focusStarted();
    }
    function stopFocus() {
        if (!root.focusActive) return;
        root.focusPhase = "idle";
        root._phaseEnd = 0;
        root.focusLeft = 0;
        if (root.focusDnd) Config.notifications.doNotDisturb = root._dndBefore;
        root.focusEnded();
    }
    function _enterPhase(phase) {
        root.focusPhase = phase;
        root._phaseEnd = Date.now() + (phase === "focus" ? root.focusMinutes : root.breakMinutes) * 60000;
        root._tick();
    }

    // ── Clock ─────────────────────────────────────────────────────────
    readonly property bool anyRunning: countdownRunning || stopwatchRunning || focusActive
    Timer {
        interval: 1000
        repeat: true
        running: root.anyRunning
        onTriggered: root._tick()
    }

    function _tick() {
        const now = Date.now();
        if (root._countdownEnd > 0) {
            root.countdownLeft = Math.max(0, Math.ceil((root._countdownEnd - now) / 1000));
            if (root.countdownLeft === 0) {
                root._countdownEnd = 0;
                EventBus.notificationRequested("Timer finished", root._fmt(root.countdownTotal) + " timer is done", "critical");
                EventBus.islandEvent("timer", { text: "Timer finished" });
            }
        }
        if (root.stopwatchRunning) root.stopwatchMs = root._swAccum + (now - root._swStart);
        else root.stopwatchMs = root._swAccum;
        if (root.focusActive) {
            root.focusLeft = Math.max(0, Math.ceil((root._phaseEnd - now) / 1000));
            if (root.focusLeft === 0) {
                if (root.focusPhase === "focus") {
                    EventBus.notificationRequested("Focus session complete", "Take a " + root.breakMinutes + "-minute break.", "normal");
                    EventBus.islandEvent("timer", { text: "Break time" });
                    root._enterPhase("break");
                } else {
                    root.focusRound += 1;
                    EventBus.notificationRequested("Break over", "Focus round " + root.focusRound + " started.", "normal");
                    root._enterPhase("focus");
                }
            }
        }
    }

    function _fmt(s) {
        const m = Math.floor(s / 60), r = s % 60;
        return m >= 60 ? Math.floor(m / 60) + ":" + String(m % 60).padStart(2, "0") + ":" + String(r).padStart(2, "0")
                       : m + ":" + String(r).padStart(2, "0");
    }
    function format(seconds) { return root._fmt(Math.max(0, Math.round(seconds))); }
}
