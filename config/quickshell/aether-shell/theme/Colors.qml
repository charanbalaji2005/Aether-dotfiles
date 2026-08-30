pragma Singleton
import Quickshell

// Original AetherOS color system: deep space background with a soft
// periwinkle/violet accent pair. Every color used anywhere in the shell
// should come from here — nothing outside theme/ should hardcode a hex value.
Singleton {
    readonly property color bg0: "#0A0C12"
    readonly property color bg1: "#12141C"
    readonly property color bg2: "#1B1E29"

    readonly property color glass: "#1E212E"
    readonly property real glassOpacity: 0.62

    readonly property color border: "#2A2E3D"
    readonly property color borderStrong: "#3A3F52"

    // Not readonly: shell.qml binds this to Config.appearance.accent so the
    // Settings app can change it live. Everything else in theme/ stays a
    // fixed constant — accent is the one token users are meant to customize.
    property color accent: "#7C9CFF"
    readonly property color accentAlt: "#B48CFF"

    readonly property color textPrimary: "#EDEFF7"
    readonly property color textSecondary: "#AEB3C7"
    readonly property color textMuted: "#7E8399"

    readonly property color success: "#4ADE80"
    readonly property color warning: "#FBBF24"
    readonly property color danger: "#F87171"
    readonly property color info: "#38BDF8"

    function withAlpha(base, alpha) {
        return Qt.rgba(base.r, base.g, base.b, alpha);
    }
}
