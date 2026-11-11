pragma Singleton
import QtQuick
import Quickshell
import "Palettes.js" as Palettes

// AetherOS colour system. Every colour used anywhere in the shell comes
// from here — nothing outside theme/ hardcodes a hex value.
//
// The tokens are resolved from a palette (theme/Palettes.js, shared with the
// Python backend that themes terminals and Hyprland borders). The built-in
// "aether" palette has dark and light variants; named schemes (Nord,
// Catppuccin, …) are inherently one or the other.
//
// Writable inputs — bound once at the shell root (shell.qml) so theme/
// stays config-agnostic: preferDark, palette, accentInput, glassOpacity,
// highContrast, colorBlind. `dark` and `accent` are the *effective* values
// every component reads.
Singleton {
    id: root

    property bool preferDark: true
    property string palette: "aether"
    // Validated user themes, id -> palette (bound from ThemeService).
    property var userPalettes: ({})
    property color accentInput: "#7C9CFF"
    // A custom accent only applies to the built-in palette; named schemes
    // keep their own so they stay recognisable.
    readonly property bool useCustomAccent: palette === "aether" || !_known
    property real glassOpacity: 0.78
    property bool highContrast: false
    property bool colorBlind: false

    readonly property bool _known: Palettes.palettes[palette] !== undefined || (userPalettes && userPalettes[palette] !== undefined)
    readonly property var p: Palettes.resolve(palette, preferDark, userPalettes)
    // The effective light/dark of the active palette (named schemes decide it).
    readonly property bool dark: p.dark

    // ── Surfaces ───────────────────────────────────────────────────────
    readonly property color bg0: p.bg0
    readonly property color bg1: p.bg1
    readonly property color bg2: p.bg2
    readonly property color glass: p.glass
    readonly property color surface: p.surface
    readonly property color surfaceHover: p.surfaceHover
    readonly property color surfaceActive: p.surfaceActive
    readonly property color border: highContrast ? textMuted : p.border
    readonly property color borderStrong: highContrast ? textSecondary : p.borderStrong
    // Subtle top highlight on glass edges (the "sheen").
    readonly property color highlight: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.8)

    // ── Accent ─────────────────────────────────────────────────────────
    readonly property color accent: useCustomAccent ? accentInput : p.accent
    readonly property color accentAlt: p.accentAlt
    // Foreground on an accent fill: dark ink on light accents, white on dark.
    readonly property color onAccent: _luma(accent) > 0.6 ? "#0A0C12" : "#FFFFFF"
    readonly property color accentSoft: withAlpha(accent, dark ? 0.18 : 0.14)

    // ── Text ───────────────────────────────────────────────────────────
    readonly property color textPrimary: highContrast ? (dark ? "#FFFFFF" : "#000000") : p.text
    readonly property color textSecondary: highContrast ? (dark ? "#E6E8F0" : "#1A1C24") : p.text2
    readonly property color textMuted: highContrast ? (dark ? "#C4C8D6" : "#33364A") : p.text3

    // ── Status (Okabe-Ito under colour-blind mode) ─────────────────────
    readonly property color success: colorBlind ? Palettes.colorBlindStatus.success : p.success
    readonly property color warning: colorBlind ? Palettes.colorBlindStatus.warning : p.warning
    readonly property color danger: colorBlind ? Palettes.colorBlindStatus.danger : p.danger
    readonly property color info: colorBlind ? Palettes.colorBlindStatus.info : p.info

    // ── Effects ────────────────────────────────────────────────────────
    readonly property color scrim: Qt.rgba(0, 0, 0, dark ? 0.38 : 0.22)
    readonly property color shadow: Qt.rgba(0, 0, 0, dark ? 0.45 : 0.16)
    // High contrast removes translucency: text must sit on a solid surface.
    readonly property real effectiveGlassOpacity: highContrast ? 0.97 : glassOpacity

    // Palette metadata for pickers: [{ id, label, dark, accent, bg }]
    readonly property var paletteList: {
        const out = [];
        const ids = Palettes.ids();
        for (let i = 0; i < ids.length; i++) {
            const e = Palettes.palettes[ids[i]];
            out.push({ id: ids[i], label: e.label, dark: e.dark, accent: e.accent, bg: e.bg0, surface: e.surface, user: false });
        }
        for (const id in (userPalettes || {})) {
            const e = userPalettes[id];
            out.push({ id: id, label: e.label, dark: e.dark, accent: e.accent, bg: e.bg0, surface: e.surface, user: true });
        }
        return out;
    }

    function withAlpha(base, alpha) {
        return Qt.rgba(base.r, base.g, base.b, alpha);
    }

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
    }

    // Colour for a 0-1 load value: accent → warning → danger.
    function load(value) {
        if (value >= 0.9) return danger;
        if (value >= 0.75) return warning;
        return accent;
    }

    // Colour for a temperature in °C.
    function temperature(c) {
        if (c >= 90) return danger;
        if (c >= 78) return warning;
        return textSecondary;
    }

    function _luma(c) {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    }
}
