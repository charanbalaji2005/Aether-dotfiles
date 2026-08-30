pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property int fast: 120
    readonly property int normal: 200
    readonly property int slow: 320
    readonly property int easeStandard: Easing.OutCubic
    readonly property int easeEmphasized: Easing.OutBack

    // Bound to Config.general.reducedMotion at the shell root (shell.qml) —
    // every Behavior block in the shell should gate on this rather than
    // each importing core/Config directly, keeping theme/ config-agnostic
    // except for this one deliberate bridge point (same pattern as
    // Colors.accent).
    property bool reducedMotion: false
}
