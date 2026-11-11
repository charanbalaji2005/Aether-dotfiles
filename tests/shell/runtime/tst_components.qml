import QtQuick
import QtQuick.Window
import "../theme"
import "../components"
import "Assert.js" as A

Window {
    id: win
    width: 520; height: 260; visible: true
    color: "#000000"

    Rectangle { anchors.fill: parent; color: "#101010" }

    // Battery families at 50 %, normal state, red tone so pixels are unambiguous.
    Row {
        id: batteries
        x: 10; y: 10; spacing: 14
        Repeater {
            model: ["classic", "outline", "filled", "segmented", "circular", "percent", "compact", "bar"]
            delegate: BatteryIcon { required property string modelData; style: modelData; level: 0.5; colorNormal: "#ff0000" }
        }
    }
    BatteryIcon { id: low; x: 10; y: 40; level: 0.15; state: "low"; colorLow: "#00ff00" }
    BatteryIcon { id: chg; x: 50; y: 40; level: 0.6; charging: true; colorCharging: "#0000ff" }

    RadialGauge { id: gauge; x: 10; y: 70; width: 110; height: 110; value: 0.8; label: "CPU"; color: "#ff00ff" }
    RadialGauge { id: na; x: 130; y: 70; width: 110; height: 110; available: false; label: "GPU" }

    property bool state: false
    Switch { id: sw; x: 260; y: 70; checked: win.state; onToggled: function(v) { win.state = v; } }

    property real vol: 0.5
    property var moves: []
    Slider { id: sl; x: 260; y: 120; width: 200; value: win.vol; onMoved: function(v) { win.moves.push(v); win.vol = v; } }

    GlassPanel { id: glass; x: 260; y: 160; width: 200; height: 80; radius: 18; focused: true }

    property int step: 0
    Timer {
        interval: 120; repeat: true; running: true
        onTriggered: {
            step++;
            if (step === 1) {
                sw.forceActiveFocus();
                A.ok(sw.activeFocus, "switch takes keyboard focus");
                // Simulate Space through the key handler path.
                sw.toggled(!sw.checked);
                A.ok(win.state === true && sw.checked === true, "switch binding survives a toggle");
            }
            if (step === 2) {
                A.ok(sw.stretch >= 0, "knob stretch is defined while moving");
            }
            if (step === 8) {
                A.ok(sw.checked, "switch still bound after spring settles");
                sl.forceActiveFocus();
                sl._step(0.05);
                A.near(win.vol, 0.55, 1e-9, "slider keyboard step +5%");
                sl._step(-0.10);
                A.near(win.vol, 0.45, 1e-9, "slider keyboard step -10%");
                sl._step(-5);
                A.near(win.vol, 0, 1e-9, "slider clamps at the minimum");
                A.ok(na.valueText === "—", "unavailable gauge shows a dash, not a zero");
            }
            if (step === 16) {
                win.contentItem.grabToImage(function(r) {
                    const p = "/tmp/aether-components-" + Date.now() + ".png";
                    r.saveToFile(p);
                    console.log("SHOT " + p);
                    // classic battery at x 10..34: left of fill red, right part empty (dark)
                    console.log("PIXMIN battery classic: filled half is red|14|16|r|150");
                    console.log("PIXMAX battery classic: empty half is not filled|28|16|r|90");
                    console.log("PIXMIN battery low state uses the low colour|12|46|g|150");
                    console.log("PIXMIN battery charging uses the charging colour|56|46|b|150");
                    // gauge at 80% magenta: right side (3 o'clock) of the arc is lit
                    console.log("PIXMIN gauge arc drawn at the top|65|73|r|120");
                    console.log("PIXMAX unavailable gauge draws no value arc|143|155|b|60");
                    // switch on: track is the accent, left area
                    console.log("PIXDIFF switch on differs from the background|266|82|200|200|60");
                    Qt.exit(A.failures ? 1 : 0);
                });
            }
        }
    }
}
