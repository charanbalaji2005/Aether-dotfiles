pragma Singleton
import Quickshell

Singleton {
    readonly property int spaceXxs: 2
    readonly property int spaceXs: 4
    readonly property int spaceSm: 8
    readonly property int spaceMd: 12
    readonly property int spaceLg: 16
    readonly property int spaceXl: 24
    readonly property int spaceXxl: 32

    readonly property int radiusSm: 8
    readonly property int radiusMd: 14
    readonly property int radiusLg: 20
    readonly property int radiusXl: 26
    readonly property int radiusPill: 999

    // Default bar height; the live value is Config.bar.height.
    readonly property int barHeight: 38
    readonly property int barMargin: 8
    readonly property int borderWidth: 1

    readonly property int iconSm: 14
    readonly property int iconMd: 16
    readonly property int iconLg: 20
    readonly property int iconXl: 28

    // Popup panel widths.
    readonly property int controlCenterWidth: 380
    readonly property int notificationWidth: 380
    readonly property int toastWidth: 360
}
