pragma Singleton
import Quickshell

// Type scale. `scale` follows Settings → Accessibility → UI scale.
Singleton {
    id: root

    property real scale: 1.0
    function s(v) { return Math.round(v * root.scale); }

    readonly property string family: "Manrope"
    readonly property string familyFallback: "Inter, Noto Sans, sans-serif"
    readonly property string familyMono: "JetBrains Mono"
    // Display numerals (clocks, gauges): tabular so digits don't jitter.
    readonly property string familyDisplay: "Manrope"

    readonly property int sizeXs: s(10)
    readonly property int sizeSm: s(12)
    readonly property int sizeMd: s(13)
    readonly property int sizeLg: s(15)
    readonly property int sizeXl: s(19)
    readonly property int sizeXxl: s(24)
    readonly property int sizeDisplay: s(40)
    readonly property int sizeHero: s(96)

    readonly property int weightLight: 300
    readonly property int weightRegular: 400
    readonly property int weightMedium: 500
    readonly property int weightSemibold: 600
    readonly property int weightBold: 700
}
