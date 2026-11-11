pragma Singleton
import QtQuick
import Quickshell

// Glass material presets (Settings → Appearance → Glass). Each maps to a
// panel tint opacity plus how much frost (film grain) and specular the
// shader material adds. "custom" uses the panel-opacity slider directly;
// "adaptive" goes more opaque on light, busy wallpapers and on battery.
Singleton {
    id: root

    property string style: "medium"
    property real customOpacity: 0.80
    property bool onBattery: false

    readonly property var presets: ({
        "opaque":   { opacity: 0.98, frost: 0.00, specular: 0.00, label: "Opaque" },
        "light":    { opacity: 0.90, frost: 0.020, specular: 0.05, label: "Light glass" },
        "medium":   { opacity: 0.78, frost: 0.035, specular: 0.08, label: "Medium glass" },
        "heavy":    { opacity: 0.62, frost: 0.050, specular: 0.11, label: "Heavy glass" },
        "ultra":    { opacity: 0.42, frost: 0.060, specular: 0.14, label: "Ultra-clear" },
        "adaptive": { opacity: 0.74, frost: 0.040, specular: 0.08, label: "Adaptive" },
        "custom":   { opacity: -1,   frost: 0.035, specular: 0.08, label: "Custom" }
    })

    readonly property var current: presets[style] || presets.medium
    readonly property real panelOpacity: {
        if (style === "custom") return customOpacity;
        if (style === "adaptive") return onBattery ? 0.9 : current.opacity;
        return current.opacity;
    }
    readonly property real frost: current.frost
    readonly property real specular: current.specular
}
