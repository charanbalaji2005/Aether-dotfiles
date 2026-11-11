pragma Singleton
import Quickshell

// Spacing, radii and sizes. `scale` (Settings → Accessibility → UI scale)
// multiplies spacing and sizes; `cornerScale` (Settings → Appearance)
// multiplies radii. Both are bound at the shell root.
Singleton {
    id: root

    property real scale: 1.0
    property real cornerScale: 1.0

    function s(v) { return Math.round(v * root.scale); }
    function r(v) { return Math.round(v * root.cornerScale); }

    readonly property int spaceXxs: s(2)
    readonly property int spaceXs: s(4)
    readonly property int spaceSm: s(8)
    readonly property int spaceMd: s(12)
    readonly property int spaceLg: s(16)
    readonly property int spaceXl: s(24)
    readonly property int spaceXxl: s(32)

    readonly property int radiusSm: r(8)
    readonly property int radiusMd: r(14)
    readonly property int radiusLg: r(20)
    readonly property int radiusXl: r(26)
    readonly property int radiusPill: 999

    // Default bar height; the live value is Config.bar.height.
    readonly property int barHeight: 38
    readonly property int barMargin: 8
    readonly property int borderWidth: 1
    readonly property int focusRing: 2

    readonly property int iconSm: s(14)
    readonly property int iconMd: s(16)
    readonly property int iconLg: s(20)
    readonly property int iconXl: s(28)

    // Popup panel widths.
    readonly property int controlCenterWidth: s(380)
    readonly property int notificationWidth: s(380)
    readonly property int toastWidth: s(360)

    // Elevation: shadow blur radius and offset per level (0 = flat).
    function elevationBlur(level) { return [0, 10, 18, 28, 40][Math.max(0, Math.min(4, level))]; }
    function elevationOffset(level) { return [0, 2, 4, 8, 12][Math.max(0, Math.min(4, level))]; }
}
