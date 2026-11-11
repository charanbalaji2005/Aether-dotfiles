import QtQuick
import QtQuick.Window
import "../theme"
import "../graphics"
import "Assert.js" as A

Window {
    id: win
    width: 320; height: 180; visible: true
    color: "black"

    WallpaperStage {
        id: stage
        anchors.fill: parent
        path: "/tmp/aether-red.png"
        transition: "circle"
        duration: 400
    }
    property var started: []
    property int finished: 0
    Connections {
        target: stage
        function onTransitionStarted(m) { win.started.push(m); }
        function onTransitionFinished() { win.finished++; }
    }

    property int step: 0
    property bool sawMidway: false
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            step++;
            if (step === 4) {
                A.ok(stage.shownPath === "/tmp/aether-red.png" && !stage.transitioning, "initial wallpaper shown without a transition");
                stage.path = "/tmp/aether-blue.png";
            }
            if (step > 4 && step < 12 && stage.transitioning && stage.progress > 0.2 && stage.progress < 0.8 && !sawMidway) {
                sawMidway = true;
                win.contentItem.grabToImage(function(r) {
                    const p = "/tmp/aether-stage-mid-" + Date.now() + ".png"; r.saveToFile(p);
                    console.log("SHOT " + p);
                    console.log("PIXMIN mid-transition: old picture still at the edge (no black frame)|2|2|r|200");
                    console.log("PIXMIN mid-transition: new picture revealed at the centre|160|90|b|200");
                });
            }
            if (step === 14) {
                A.ok(sawMidway, "a circle transition was observed part-way");
                A.ok(!stage.transitioning && stage.shownPath === "/tmp/aether-blue.png", "transition completed and swapped layers");
                A.ok(win.started[0] === "circle", "circle mode used when shaders are available");
                // Without shaders, shader-only modes degrade to fade.
                ShaderLibrary.failed = { "transition": true };
                stage.transition = "dissolve";
                stage.path = "/tmp/aether-green.png";
            }
            if (step === 24) {
                A.ok(win.started[1] === "fade", "dissolve falls back to fade without the shader (got " + win.started[1] + ")");
                A.ok(stage.shownPath === "/tmp/aether-green.png" && !stage.transitioning, "fallback transition completed");
                ShaderLibrary.failed = {};
                // Rapid changes: the latest request wins and nothing wedges.
                stage.transition = "slide";
                stage.path = "/tmp/aether-red.png";
                stage.path = "/tmp/aether-blue.png";
            }
            if (step === 40) {
                A.ok(stage.shownPath === "/tmp/aether-blue.png" && !stage.transitioning, "rapid changes settle on the last wallpaper");
                Motion.reducedMotionSetting = true;
                const before = win.finished;
                stage.path = "/tmp/aether-red.png";
            }
            if (step === 44) {
                A.ok(stage.shownPath === "/tmp/aether-red.png" && !stage.transitioning, "reduced motion swaps instantly");
                A.ok(win.started.indexOf("none") < 0, "no transition signalled under reduced motion");
                Motion.reducedMotionSetting = false;
                win.contentItem.grabToImage(function(r) {
                    const p = "/tmp/aether-stage-end-" + Date.now() + ".png"; r.saveToFile(p);
                    console.log("SHOT " + p);
                    console.log("PIX final frame shows the current wallpaper|160|90|255|0|0|6");
                    Qt.exit(A.failures ? 1 : 0);
                });
            }
        }
    }
}
