import QtQuick
import QtQuick.Window
import "../animation"
import "../theme"
import "../core"
import "Assert.js" as A

// Spring engine: converges, settles, stops its frame callback, keeps
// velocity across interruptions, snaps under reduced motion, and reports
// to the coordinator.
Window {
    width: 100; height: 100; visible: true

    SpringValue { id: s; preset: "smooth" }
    SpringValue { id: b; preset: "bouncy" }
    property real maxB: 0
    Connections { target: b; function onValueChanged() { if (b.value > maxB) maxB = b.value; } }
    property int settledCount: 0
    Connections { target: s; function onSettled() { settledCount++; } }

    property int phase: 0
    property real vBefore: 0
    property real xBefore: 0

    Timer {
        interval: 50; repeat: true; running: true
        property int ticks: 0
        onTriggered: {
            ticks++;
            switch (phase) {
            case 0:
                A.ok(!s.running, "idle spring does not run");
                A.ok(AnimationCoordinator.active === 0, "coordinator idle at start");
                s.target = 100; b.target = 1;
                A.ok(s.running, "target change wakes the spring");
                A.ok(AnimationCoordinator.active === 2, "coordinator counts two running springs");
                phase = 1; ticks = 0; break;
            case 1:
                if (ticks === 3) {
                    xBefore = s.value; vBefore = s.velocity;
                    A.ok(s.value > 1 && s.value < 100, "moving part-way after 150ms (value " + s.value.toFixed(2) + ")");
                    A.ok(s.velocity > 0, "positive velocity towards target");
                    // Interrupt: reverse direction. Velocity must carry over.
                    s.target = 0;
                    A.ok(Math.abs(s.value - xBefore) < 1e-9, "interruption does not jump the value");
                    A.ok(s.velocity === vBefore, "interruption preserves velocity");
                }
                if (ticks === 5) A.ok(s.value > xBefore, "momentum carries past the interruption point first");
                if (!s.running && !b.running && ticks > 5) {
                    A.near(s.value, 0, 1e-6, "smooth spring settles exactly on target");
                    A.ok(s.velocity === 0, "settled velocity is zero");
                    A.ok(settledCount >= 1, "settled() emitted");
                    A.near(b.value, 1, 1e-6, "bouncy spring settles on target");
                    A.ok(maxB > 1.05, "bouncy preset overshoots (peak " + maxB.toFixed(3) + ")");
                    A.ok(AnimationCoordinator.active === 0, "coordinator back to zero when all springs rest");
                    phase = 2; ticks = 0;
                }
                if (ticks > 80) { A.ok(false, "springs settled within 4s"); phase = 2; }
                break;
            case 2:
                Motion.reducedMotionSetting = true;
                s.target = 42;
                A.ok(s.value === 42 && !s.running, "reduced motion snaps without running");
                Motion.reducedMotionSetting = false;
                Motion.springsSetting = false;
                s.target = 7;
                A.ok(s.value === 7 && !s.running, "springs disabled snaps");
                Motion.springsSetting = true;
                s.snap(0);
                s.impulse(500);
                A.ok(s.running && s.velocity === 500, "impulse adds velocity and wakes");
                phase = 3; ticks = 0; break;
            case 3:
                if (!s.running) {
                    A.near(s.value, 0, 1e-6, "impulse decays back to target");
                    A.ok(AnimationCoordinator.active === 0, "snap/impulse leave the coordinator balanced");
                    Qt.exit(A.failures ? 1 : 0);
                }
                if (ticks > 80) { A.ok(false, "impulse settled"); Qt.exit(1); }
                break;
            }
        }
    }
}
