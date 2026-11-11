import QtQuick
import QtQuick.Window
import "../theme"
import "../graphics"
import "Assert.js" as A

// Renders every shader through the real RHI and checks pixels.
Window {
    id: win
    width: 640; height: 360; visible: true
    color: "black"

    // Transition sources: solid red and solid blue layers.
    Rectangle { id: red; width: 200; height: 120; color: "#ff0000"; layer.enabled: true; visible: false }
    Rectangle { id: blue; width: 200; height: 120; color: "#0000ff"; layer.enabled: true; visible: false }

    WallpaperTransition { id: tr; x: 0; y: 0; width: 200; height: 120; from: red; to: blue; mode: "wipe"; progress: 0.5; softness: 0.02 }
    WallpaperTransition { id: circ; x: 210; y: 0; width: 200; height: 120; from: red; to: blue; mode: "circle"; progress: 0.3; softness: 0.02 }

    Rectangle { id: base; x: 420; y: 0; width: 200; height: 120; color: "#202020" }
    GlassMaterial { id: glass; anchors.fill: base; radius: 20; frost: 0.08; specular: 0.3; pointer: Qt.point(0.5, 0.5); pointerInside: true }

    Item { id: glowHost; x: 40; y: 170; width: 160; height: 100 }
    GlowEdge { id: glow; anchors.fill: glowHost; radius: 16; colorA: "#00ffff"; colorB: "#00ffff"; active: false; intensity: 1 }

    AuroraSurface { id: aurora; x: 240; y: 150; width: 200; height: 120; running: false; base: "#000000"; colorA: "#ff0000"; colorB: "#00ff00"; colorC: "#0000ff"; strength: 1 }

    Timer {
        interval: 1500; running: true
        onTriggered: {
            A.ok(tr.shaderActive, "transition shader active");
            A.ok(Object.keys(ShaderLibrary.failed).length === 0, "no shader failed to load: " + JSON.stringify(ShaderLibrary.failed));
            win.contentItem.grabToImage(function(r) {
                const path = "/tmp/aether-shaders-" + Date.now() + ".png";
                A.ok(r.saveToFile(path), "frame saved");
                console.log("SHOT " + path);
                // Wipe at 50% moving right: left half new (blue), right half old (red).
                console.log("PIX wipe: left side shows the new image|20|60|0|0|255|8");
                console.log("PIX wipe: right side still shows the old image|180|60|255|0|0|8");
                // Circle at 30% from the centre: centre new, corner old.
                console.log("PIX circle: centre revealed|310|60|0|0|255|8");
                console.log("PIX circle: corner not yet revealed|212|2|255|0|0|8");
                // Glass: lit centre brighter than the base; corner outside the radius untouched.
                console.log("PIXMIN glass: specular brightens the lit centre|520|60|r|60");
                console.log("PIX glass: corner outside the radius untouched|421|1|32|32|32|3");
                // Glow: cyan on the edge, interior dark.
                console.log("PIXMIN glow: cyan on the edge (g)|120|170|g|60");
                console.log("PIXMAX glow: no red in cyan glow|120|170|r|30");
                console.log("PIXMAX glow: interior stays dark|120|220|g|10");
                // Aurora: coloured and varying.
                console.log("PIXDIFF aurora: varies across the surface|260|170|420|250|15");
                Qt.exit(A.failures ? 1 : 0);
            });
        }
    }
}
