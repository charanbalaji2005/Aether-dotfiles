import QtQuick
import "../theme"
import "../core"

// A damped harmonic oscillator that chases `target`.
//
//   SpringValue { id: lift; target: hovered ? 1 : 0; preset: "snappy" }
//   Item { y: -6 * lift.value; scale: 1 + 0.04 * lift.value }
//
// Why not a NumberAnimation: changing the target mid-flight keeps the
// current *velocity*, so interrupted motion stays continuous instead of
// restarting from rest — the property that makes gestures feel physical.
//
// Integration: semi-implicit Euler at a fixed 1/240 s sub-step (stable for
// every preset in Motion.springs), driven by a FrameAnimation that only
// runs while the spring is moving. At rest it costs nothing: no timer, no
// per-frame callback. Frames are reported to AnimationCoordinator, which
// is how the shell measures its own frame pacing.
//
// Reduced motion or springs disabled: `value` snaps to `target`.
QtObject {
    id: root

    property real target: 0
    property real value: 0
    property real velocity: 0

    property string preset: "smooth"
    property real stiffness: Motion.spring(preset).stiffness
    property real damping: Motion.spring(preset).damping
    property real mass: Motion.spring(preset).mass
    // Settled when both displacement and speed are below these.
    property real epsilon: 0.001
    property real velocityEpsilon: 0.01
    // Stops runaway values from a bad impulse.
    property real maxVelocity: 1e5
    property bool enabled: true

    readonly property bool running: _frames.running
    readonly property bool animated: enabled && Motion.useSprings

    signal settled()

    // Come to rest immediately — at `v` (which becomes the target) or at
    // the current target.
    function snap(v) {
        if (v !== undefined && v !== root.target) {
            root._snapping = true;
            root.target = v;
            root._snapping = false;
        }
        root.value = root.target;
        root.velocity = 0;
        _sleep();
    }
    property bool _snapping: false

    // Add velocity (units/s), e.g. the release velocity of a drag.
    function impulse(dv) {
        if (!root.animated) return;
        root.velocity = Math.max(-root.maxVelocity, Math.min(root.maxVelocity, root.velocity + dv));
        _wake();
    }

    function _wake() {
        if (!_frames.running) {
            _frames.running = true;
            AnimationCoordinator.begin();
        }
    }

    function _sleep() {
        if (_frames.running) {
            _frames.running = false;
            AnimationCoordinator.end();
        }
    }

    function _step(dt) {
        // Time scale from the user's animation-speed setting.
        const s = Motion.speed > 0.1 ? Motion.speed : 1.0;
        let remaining = Math.min(dt, 0.064) * s;   // clamp: a stalled frame must not explode the system
        const h = 1 / 240;
        let x = root.value, v = root.velocity;
        const k = root.stiffness, c = root.damping, m = root.mass > 0 ? root.mass : 1;
        while (remaining > 1e-6) {
            const step = Math.min(h, remaining);
            const a = (-k * (x - root.target) - c * v) / m;
            v += a * step;
            x += v * step;
            remaining -= step;
        }
        if (!isFinite(x) || !isFinite(v)) { x = root.target; v = 0; }
        root.velocity = Math.max(-root.maxVelocity, Math.min(root.maxVelocity, v));
        if (Math.abs(x - root.target) < root.epsilon && Math.abs(root.velocity) < root.velocityEpsilon) {
            root.value = root.target;
            root.velocity = 0;
            _sleep();
            root.settled();
        } else {
            root.value = x;
        }
    }

    onTargetChanged: {
        if (root._snapping) return;
        if (!root.animated) { snap(); return; }
        _wake();
    }
    onAnimatedChanged: if (!animated) snap()

    property FrameAnimation _frames: FrameAnimation {
        running: false
        onTriggered: {
            AnimationCoordinator.frame(frameTime);
            root._step(frameTime);
        }
    }

    Component.onDestruction: _sleep()
}
