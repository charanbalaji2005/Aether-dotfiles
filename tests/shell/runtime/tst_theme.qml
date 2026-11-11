import QtQuick
import QtQuick.Window
import "../theme"
import "Assert.js" as A

Window {
    width: 10; height: 10; visible: true
    Component.onCompleted: {
        Colors.palette = "aether"; Colors.preferDark = true; Colors.accentInput = "#ff0000";
        A.colorNear(Colors.bg0, 0x0A, 0x0C, 0x12, 1, "aether dark bg0");
        A.colorNear(Colors.accent, 255, 0, 0, 1, "custom accent applies to the built-in palette");
        Colors.preferDark = false;
        A.ok(!Colors.dark, "aether follows the light preference");
        A.colorNear(Colors.bg0, 0xEE, 0xF0, 0xF6, 1, "aether light bg0");
        Colors.palette = "nord"; Colors.preferDark = true;
        A.colorNear(Colors.bg0, 0x24, 0x29, 0x33, 1, "nord bg0");
        A.colorNear(Colors.accent, 0x88, 0xC0, 0xD0, 1, "named palette keeps its own accent");
        Colors.palette = "catppuccin-latte";
        A.ok(!Colors.dark, "latte is a light palette regardless of preference");
        Colors.palette = "does-not-exist";
        A.colorNear(Colors.bg0, 0x0A, 0x0C, 0x12, 1, "unknown palette falls back to built-in");
        Colors.colorBlind = true;
        A.colorNear(Colors.success, 0x00, 0x72, 0xB2, 1, "colour-blind success is Okabe-Ito blue");
        Colors.colorBlind = false; Colors.highContrast = true;
        A.colorNear(Colors.textPrimary, 255, 255, 255, 1, "high contrast text is pure white on dark");
        A.ok(Colors.effectiveGlassOpacity > 0.95, "high contrast makes glass opaque");
        Colors.highContrast = false;
        A.ok(Colors.paletteList.length === 18, "18 built-in palettes listed (" + Colors.paletteList.length + ")");

        Metrics.scale = 1.25;
        A.ok(Metrics.spaceLg === 20, "UI scale multiplies spacing");
        Metrics.cornerScale = 0;
        A.ok(Metrics.radiusMd === 0, "corner scale 0 squares corners");
        Typography.scale = 1.5;
        A.ok(Typography.sizeMd === 20, "UI scale multiplies type");

        Motion.reducedMotionSetting = true;
        A.ok(Motion.normal === 0 && Motion.staggerDelay(5) === 0, "reduced motion zeroes durations");
        Motion.reducedMotionSetting = false; Motion.userSpeed = 2.0;
        A.ok(Motion.normal === 100, "speed 2x halves durations");
        A.ok(Motion.staggerDelay(50) === Motion.staggerMax * Motion.stagger, "stagger is capped");
        const sp = Motion.springs;
        for (const k in sp) {
            const z = sp[k].damping / (2 * Math.sqrt(sp[k].stiffness * sp[k].mass));
            A.ok(z > 0.3 && z <= 1.05, "spring '" + k + "' damping ratio sane (" + z.toFixed(2) + ")");
        }
        Materials.style = "ultra";
        A.ok(Materials.panelOpacity < 0.5, "ultra glass is mostly clear");
        Materials.style = "custom"; Materials.customOpacity = 0.66;
        A.ok(Materials.panelOpacity === 0.66, "custom glass uses the slider");
        Materials.style = "adaptive"; Materials.onBattery = true;
        A.ok(Materials.panelOpacity >= 0.9, "adaptive glass goes opaque on battery");
        Qt.exit(A.failures ? 1 : 0);
    }
}
