import QtQuick

// Measures pointer velocity for gesture-driven animation.
//
//   GestureTracker { id: track }
//   DragHandler { onActiveChanged: active ? track.reset(x) : spring.impulse(track.velocity)
//                 onTranslationChanged: track.sample(translation.x) }
//
// Velocity is a least-squares slope over the last 100 ms of samples, which
// is far less noisy than the last two points (touchpads deliver bursty
// events). Units: property units per second.
QtObject {
    id: root

    property int windowMs: 100
    property var _samples: []
    readonly property real velocity: _fit(_samples)
    // Distance travelled since reset().
    property real distance: 0
    property real _origin: 0

    function reset(pos) {
        root._origin = pos || 0;
        root.distance = 0;
        root._samples = [];
    }

    function sample(pos) {
        const now = Date.now();
        const kept = root._samples.filter(function(s) { return now - s.t <= root.windowMs; });
        kept.push({ t: now, p: pos });
        root._samples = kept;
        root.distance = pos - root._origin;
    }

    function _fit(list) {
        if (!list || list.length < 2) return 0;
        const t0 = list[0].t;
        let n = list.length, st = 0, sp = 0, stt = 0, stp = 0;
        for (let i = 0; i < n; i++) {
            const t = (list[i].t - t0) / 1000;
            st += t; sp += list[i].p; stt += t * t; stp += t * list[i].p;
        }
        const den = n * stt - st * st;
        return den > 1e-9 ? (n * stp - st * sp) / den : 0;
    }
}
