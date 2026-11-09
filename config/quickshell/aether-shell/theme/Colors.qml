pragma Singleton
import QtQuick
import Quickshell

// AetherOS colour system. Every colour used anywhere in the shell comes
// from here — nothing outside theme/ hardcodes a hex value.
//
// Two palettes (dark: deep-space navy; light: cool paper) share one set of
// token names, so components never branch on the theme themselves.
//
// `dark`, `accent` and `glassOpacity` are the only writable tokens. They're
// bound at the shell root (shell.qml) to ThemeService / Config, which keeps
// theme/ itself config-agnostic.
Singleton {
    id: root

    property bool dark: true
    property color accent: "#7C9CFF"
    property real glassOpacity: 0.78

    // ── Surfaces ───────────────────────────────────────────────────────
    readonly property color bg0: dark ? "#0A0C12" : "#EEF0F6"
    readonly property color bg1: dark ? "#12141C" : "#F6F7FB"
    readonly property color bg2: dark ? "#1B1E29" : "#FFFFFF"

    // Base tint for translucent panels (alpha applied via glassOpacity).
    readonly property color glass: dark ? "#161925" : "#F8F9FC"
    // Elevated, opaque-ish fills inside panels (cards, rows, inputs).
    readonly property color surface: dark ? "#1E2230" : "#FFFFFF"
    readonly property color surfaceHover: dark ? "#272C3D" : "#E9ECF4"
    readonly property color surfaceActive: dark ? "#30364A" : "#DCE1EC"

    readonly property color border: dark ? "#2A2E3D" : "#D5D9E4"
    readonly property color borderStrong: dark ? "#3A3F52" : "#BCC2D1"
    // Subtle top highlight on glass edges (the "sheen").
    readonly property color highlight: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.8)

    // ── Accent ─────────────────────────────────────────────────────────
    readonly property color accentAlt: dark ? "#B48CFF" : "#7B4FE0"
    // Foreground on an accent fill: dark ink on light accents, white on dark.
    readonly property color onAccent: _luma(accent) > 0.6 ? "#0A0C12" : "#FFFFFF"
    readonly property color accentSoft: withAlpha(accent, dark ? 0.18 : 0.14)

    // ── Text ───────────────────────────────────────────────────────────
    readonly property color textPrimary: dark ? "#EDEFF7" : "#151824"
    readonly property color textSecondary: dark ? "#AEB3C7" : "#4A5068"
    readonly property color textMuted: dark ? "#7E8399" : "#7A8096"

    // ── Status ─────────────────────────────────────────────────────────
    readonly property color success: dark ? "#4ADE80" : "#15934A"
    readonly property color warning: dark ? "#FBBF24" : "#B7791F"
    readonly property color danger: dark ? "#F87171" : "#D63B3B"
    readonly property color info: dark ? "#38BDF8" : "#0B84C6"

    // ── Effects ────────────────────────────────────────────────────────
    readonly property color scrim: Qt.rgba(0, 0, 0, dark ? 0.38 : 0.22)
    readonly property color shadow: Qt.rgba(0, 0, 0, dark ? 0.45 : 0.16)

    function withAlpha(base, alpha) {
        return Qt.rgba(base.r, base.g, base.b, alpha);
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
