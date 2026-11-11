pragma Singleton
import QtQuick
import Quickshell

// Motion tokens — the AetherOS motion language.
//
// Durations are scaled by `speed` (Settings → Animation speed) and collapse
// to 0 under reduced motion, so every animation in the shell honours both
// settings without its own logic.
//
// Springs (animation/SpringValue.qml, animation/SpringBehavior.qml) use the
// physical presets below. "springs" off (Settings → Effects) or reduced
// motion turns them into plain eased animations / instant snaps.
//
// Inputs bound at the shell root: reducedMotion, speed, springsEnabled.
Singleton {
    id: root

    // Inputs. `profile` (Settings → Effects & motion) sets the character of
    // all motion; `speed` multiplies on top; `reducedMotionSetting` is the
    // older switch, kept so existing configs behave the same.
    property string profile: "smooth"         // none | reduced | balanced | smooth | premium
    property bool reducedMotionSetting: false
    property real userSpeed: 1.0
    property bool springsSetting: true

    readonly property var _profiles: ({
        "none":     { reduced: true,  speed: 1.0,  springs: false },
        "reduced":  { reduced: false, speed: 1.7,  springs: false },
        "balanced": { reduced: false, speed: 1.25, springs: true },
        "smooth":   { reduced: false, speed: 1.0,  springs: true },
        "premium":  { reduced: false, speed: 0.85, springs: true }
    })
    readonly property var _p: _profiles[profile] || _profiles.smooth

    readonly property bool reducedMotion: reducedMotionSetting || _p.reduced
    // 0.5 = twice as slow, 2.0 = twice as fast.
    readonly property real speed: Math.max(0.25, userSpeed * _p.speed)
    readonly property bool springsEnabled: springsSetting && _p.springs

    readonly property bool animate: !reducedMotion
    readonly property bool useSprings: springsEnabled && !reducedMotion

    readonly property int instant: _scale(70)
    readonly property int fast: _scale(120)
    readonly property int normal: _scale(200)
    readonly property int slow: _scale(320)
    readonly property int panel: _scale(260)
    readonly property int cinematic: _scale(620)
    // Delay between consecutive items of a staggered entrance.
    readonly property int stagger: _scale(28)
    readonly property int staggerMax: 10

    readonly property int easeStandard: Easing.OutCubic
    readonly property int easeEmphasized: Easing.OutBack
    readonly property int easeExit: Easing.InCubic
    readonly property int easeSpring: Easing.OutQuint
    readonly property int easeInOut: Easing.InOutCubic

    // Distance (px) panels travel while sliding in.
    readonly property int travel: reducedMotion ? 0 : 14

    // Physical spring presets: stiffness (N/m), damping (N·s/m), mass (kg).
    // damping ratio ζ = damping / (2·√(stiffness·mass)): ζ<1 overshoots.
    readonly property var springs: ({
        "snappy":  { stiffness: 520, damping: 38, mass: 1.0 },   // ζ≈0.83 controls, toggles
        "smooth":  { stiffness: 260, damping: 30, mass: 1.0 },   // ζ≈0.93 panels, cards
        "bouncy":  { stiffness: 380, damping: 18, mass: 1.0 },   // ζ≈0.46 playful accents (dock bounce)
        "gentle":  { stiffness: 120, damping: 22, mass: 1.0 },   // ζ≈1.0  large surfaces, wallpaper parallax
        "fluid":   { stiffness: 180, damping: 20, mass: 0.8 }    // ζ≈0.83 pointer-following
    })
    // Native SpringAnimation equivalents for SpringBehavior (Qt's own model).
    readonly property var nativeSprings: ({
        "snappy": { spring: 6.0, damping: 0.42, mass: 1.0 },
        "smooth": { spring: 3.6, damping: 0.36, mass: 1.0 },
        "bouncy": { spring: 4.2, damping: 0.18, mass: 1.0 },
        "gentle": { spring: 2.2, damping: 0.45, mass: 1.0 },
        "fluid":  { spring: 3.0, damping: 0.28, mass: 0.8 }
    })

    function spring(name) { return springs[name] || springs.smooth; }
    function nativeSpring(name) { return nativeSprings[name] || nativeSprings.smooth; }

    function staggerDelay(index) {
        return reducedMotion ? 0 : Math.min(Math.max(0, index), staggerMax) * stagger;
    }

    function _scale(ms) {
        if (reducedMotion) return 0;
        const s = speed > 0.1 ? speed : 1.0;
        return Math.round(ms / s);
    }
}
