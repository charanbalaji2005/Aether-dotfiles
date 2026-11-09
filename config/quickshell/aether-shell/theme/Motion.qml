pragma Singleton
import QtQuick
import Quickshell

// Motion tokens. Durations are scaled by `speed` (Settings → Animation
// speed) and collapse to 0 under reduced motion, so every animation in the
// shell honours both settings without its own logic.
//
// `reducedMotion` and `speed` are bound at the shell root (shell.qml) to
// Config — the same single bridge point used for Colors.
Singleton {
    id: root

    property bool reducedMotion: false
    // 0.5 = twice as slow, 2.0 = twice as fast.
    property real speed: 1.0

    readonly property int fast: _scale(120)
    readonly property int normal: _scale(200)
    readonly property int slow: _scale(320)
    readonly property int panel: _scale(260)

    readonly property int easeStandard: Easing.OutCubic
    readonly property int easeEmphasized: Easing.OutBack
    readonly property int easeExit: Easing.InCubic
    readonly property int easeSpring: Easing.OutQuint

    // Distance (px) panels travel while sliding in.
    readonly property int travel: reducedMotion ? 0 : 14

    function _scale(ms) {
        if (reducedMotion) return 0;
        const s = speed > 0.1 ? speed : 1.0;
        return Math.round(ms / s);
    }
}
