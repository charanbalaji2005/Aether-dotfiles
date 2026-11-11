pragma Singleton
import QtQuick
import Quickshell

// Shared bookkeeping for every animation in the shell.
//
// * Reference-counts running springs/transitions (`begin`/`end`), so the
//   shell knows when *anything* is animating — and, just as importantly,
//   when nothing is.
// * Measures frame pacing *only while something animates*: springs report
//   each frameTime here. Nothing is sampled while the desktop is idle.
// * Publishes `struggling` when, across the last window of animated
//   frames, more than a fifth took over 1.5× the display's frame budget.
//   PerformanceService uses it to step visual quality down (adaptive
//   quality); it recovers after sustained smooth frames.
Singleton {
    id: root

    property int active: 0
    readonly property bool animating: active > 0

    // Display refresh in Hz (bound from the focused monitor at the root).
    property real refreshRate: 60
    readonly property real budgetMs: 1000 / Math.max(30, refreshRate)

    property int windowSize: 120
    property var _times: []
    property int lateFrames: 0
    property real averageFrameMs: 0
    property bool struggling: false
    // Consecutive smooth windows needed before `struggling` clears.
    property int _smoothWindows: 0

    function begin() { root.active += 1; }
    function end() { root.active = Math.max(0, root.active - 1); }

    function frame(seconds) {
        const ms = seconds * 1000;
        if (ms <= 0 || ms > 1000) return;   // first frame / resumed from sleep
        const t = root._times;
        t.push(ms);
        if (t.length < root.windowSize) return;
        let late = 0, sum = 0;
        for (let i = 0; i < t.length; i++) {
            sum += t[i];
            if (t[i] > root.budgetMs * 1.5) late++;
        }
        root.lateFrames = late;
        root.averageFrameMs = sum / t.length;
        root._times = [];
        if (late > t.length / 5) {
            root._smoothWindows = 0;
            if (!root.struggling) root.struggling = true;
        } else if (root.struggling && ++root._smoothWindows >= 3) {
            root.struggling = false;
        }
    }

    function resetPacing() {
        root._times = [];
        root.struggling = false;
        root._smoothWindows = 0;
    }
}
