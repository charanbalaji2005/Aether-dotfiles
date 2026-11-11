import QtQuick
import "../theme"

// Drop-in spring for any numeric property, using Qt's native
// SpringAnimation (runs in the animation driver, interruptible, keeps
// velocity when the value changes mid-flight):
//
//   x: hovered ? 20 : 0
//   SpringBehavior on x { preset: "snappy" }
//
// Springs off → a short eased animation; reduced motion → instant.
Behavior {
    id: root

    property string preset: "smooth"
    // Tolerance at which the spring is considered at rest (property units).
    property real epsilon: 0.25

    enabled: Motion.animate

    // One animation object whose parameters switch, rather than two
    // animations: a Behavior holds exactly one.
    SpringAnimation {
        spring: Motion.useSprings ? Motion.nativeSpring(root.preset).spring : 30
        damping: Motion.useSprings ? Motion.nativeSpring(root.preset).damping : 1.0
        mass: Motion.nativeSpring(root.preset).mass
        epsilon: root.epsilon
    }
}
