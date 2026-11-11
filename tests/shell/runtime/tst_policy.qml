import QtQuick
import QtQuick.Window
import "../theme"
import "../policy/Pressure.js" as Pressure
import "Assert.js" as A

// GPU pressure hysteresis and motion profiles.
Window {
    width: 10; height: 10; visible: true
    Component.onCompleted: {
        const GiB = 1073741824;
        let s = Pressure.create({ vramThreshold: 0.88, gpuThreshold: 0.92 });
        const high = { usage: 0.5, vramUsed: 5.6 * GiB, vramTotal: 6 * GiB };   // 93 % VRAM (RTX 4050: 6 GiB)
        const band = { usage: 0.5, vramUsed: 5.0 * GiB, vramTotal: 6 * GiB };   // 83 %: between exit and enter
        const low = { usage: 0.2, vramUsed: 2 * GiB, vramTotal: 6 * GiB };
        s = Pressure.step(s, high); s = Pressure.step(s, high);
        A.ok(!s.active, "two hot samples are not enough (a spike doesn't flip quality)");
        s = Pressure.step(s, high);
        A.ok(s.active && s.reason.indexOf("GPU memory 93%") === 0, "three consecutive hot samples activate pressure (" + s.reason + ")");
        for (let i = 0; i < 20; i++) s = Pressure.step(s, band);
        A.ok(s.active, "inside the hysteresis band the state holds");
        for (let i = 0; i < 9; i++) s = Pressure.step(s, low);
        A.ok(s.active, "nine cool samples are not enough to recover");
        s = Pressure.step(s, low);
        A.ok(!s.active, "ten cool samples recover");
        let u = Pressure.create({});
        for (let i = 0; i < 3; i++) u = Pressure.step(u, { usage: 0.97, vramUsed: 0, vramTotal: 0 });
        A.ok(u.active && u.reason === "GPU 97% busy", "utilisation alone can trigger (" + u.reason + ")");
        let n = Pressure.create({});
        for (let i = 0; i < 10; i++) n = Pressure.step(n, { usage: null, vramUsed: null, vramTotal: null });
        A.ok(!n.active, "a GPU without telemetry is never 'under pressure'");
        let alt = Pressure.create({});
        for (let i = 0; i < 6; i++) alt = Pressure.step(alt, i % 2 ? high : low);
        A.ok(!alt.active, "alternating hot/cool never activates");

        Motion.profile = "none";
        A.ok(Motion.reducedMotion && Motion.normal === 0, "profile none = no animation");
        Motion.profile = "reduced";
        A.ok(!Motion.reducedMotion && !Motion.useSprings && Motion.normal < 200, "reduced = short, spring-free");
        Motion.profile = "premium";
        A.ok(Motion.useSprings && Motion.normal > 200, "premium = slower, springs on (" + Motion.normal + ")");
        Motion.profile = "smooth"; Motion.userSpeed = 2.0;
        A.ok(Motion.normal === 100, "user speed multiplies on top of the profile");
        Motion.userSpeed = 1.0; Motion.reducedMotionSetting = true;
        A.ok(Motion.reducedMotion, "the older reduced-motion switch still works");
        Motion.reducedMotionSetting = false;
        Colors.userPalettes = { "sunset": Object.assign({}, Colors.p, { label: "Sunset", bg0: "#123456", accent: "#FF8800" }) };
        Colors.palette = "sunset";
        A.colorNear(Colors.bg0, 0x12, 0x34, 0x56, 1, "user palettes resolve");
        A.ok(Colors.paletteList.some(function(p) { return p.id === "sunset" && p.user; }), "user palettes are listed");
        Qt.exit(A.failures ? 1 : 0);
    }
}
