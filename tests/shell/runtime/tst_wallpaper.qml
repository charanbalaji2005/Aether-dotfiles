import QtQuick
import QtQuick.Window
import "../theme"
import "../graphics"
import "Assert.js" as A

// Hidden Image items as shader textures (the wallpaper engine's design),
// and depth-map parallax actually displacing near pixels more than far.
Window {
    id: win
    width: 700; height: 380; visible: true

    Image { id: a; source: "file:///tmp/aether-red.png"; visible: false; width: 320; height: 180 }
    Image { id: b; source: "file:///tmp/aether-blue.png"; visible: false; width: 320; height: 180 }
    WallpaperTransition { id: tr; x: 0; y: 0; width: 320; height: 180; from: a; to: b; mode: "circle"; progress: 0.25; softness: 0.02 }

    // Same picture twice: pointer at rest vs. pointer at the left edge.
    // strength = 10/320 shifts near (white-depth) pixels by exactly half a
    // 20 px stripe period, so every near stripe inverts; far pixels
    // (depth 0 = focal depth) must not move at all.
    DepthImage {
        id: rest
        x: 360; y: 0; width: 320; height: 180
        source: "file:///tmp/aether-stripes.png"; depthSource: "file:///tmp/aether-depth.png"
        sourceWidth: 320; sourceHeight: 180
        strength: 0.03125; focalDepth: 0.0; offset: Qt.point(0, 0)
    }
    DepthImage {
        id: moved
        x: 0; y: 190; width: 320; height: 180
        source: "file:///tmp/aether-stripes.png"; depthSource: "file:///tmp/aether-depth.png"
        sourceWidth: 320; sourceHeight: 180
        strength: 0.03125; focalDepth: 0.0; offset: Qt.point(-1, 0)
    }

    property int step: 0
    Timer {
        interval: 400; repeat: true; running: true
        onTriggered: {
            step++;
            if (step !== 2) return;
            A.ok(a.status === Image.Ready && b.status === Image.Ready, "test images loaded");
            A.ok(rest.trueDepth && moved.trueDepth, "depth map detected: true depth mode (not the 2.5D fallback)");
            win.contentItem.grabToImage(function(r) {
                const p = "/tmp/aether-wp-" + Date.now() + ".png"; r.saveToFile(p);
                console.log("SHOT " + p);
                console.log("PIX hidden Image textures: centre revealed (new)|160|90|0|0|255|8");
                console.log("PIX hidden Image textures: corner still old|4|4|255|0|0|8");
                // Probe points sit inside stripes (computed for the 1.069 edge zoom).
                for (const x of [35, 36, 37]) {
                    console.log("PIXMIN parallax: near stripe white at rest x=" + x + "|" + (360 + x) + "|90|r|200");
                    console.log("PIXMAX parallax: near stripe inverted when moved x=" + x + "|" + x + "|280|r|55");
                }
                for (const x of [196, 197, 198]) {
                    console.log("PIXMAX parallax: far stripe black at rest x=" + x + "|" + (360 + x) + "|90|r|55");
                    console.log("PIXMAX parallax: far stripe unmoved x=" + x + "|" + x + "|280|r|55");
                }
                Qt.exit(A.failures ? 1 : 0);
            });
        }
    }
}
