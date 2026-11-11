import QtQuick
import QtQuick.Particles
import "../theme"

// Ambient particles on Qt Quick's GPU particle system (instanced quads —
// no per-particle QML objects, no shader of our own to maintain).
//
// kinds: "stars" (slow twinkling drift), "snow", "rain", "dust" (motes
// rising in light). `density` 0-1 scales the emit rate; the system is
// paused (not just hidden) whenever `running` is false, so an occluded
// desktop costs nothing.
Item {
    id: root

    property string kind: "stars"
    property real density: 0.5
    property bool running: true
    property color tint: Colors.dark ? "#FFFFFF" : Colors.textSecondary

    readonly property var spec: ({
        "stars": { rate: 18, life: 9000, size: 3, sizeVar: 2, vx: 4, vy: -3, varX: 6, varY: 6, alpha: 0.7 },
        "snow":  { rate: 40, life: 14000, size: 5, sizeVar: 3, vx: 6, vy: 38, varX: 14, varY: 10, alpha: 0.85 },
        "rain":  { rate: 120, life: 1600, size: 2, sizeVar: 1, vx: -30, vy: 900, varX: 10, varY: 120, alpha: 0.45 },
        "dust":  { rate: 14, life: 12000, size: 4, sizeVar: 3, vx: 3, vy: -12, varX: 8, varY: 6, alpha: 0.5 }
    })
    readonly property var s: spec[kind] || spec.stars
    // Emit rate scales with area so a 4K screen isn't sparse.
    readonly property real areaScale: Math.max(0.3, (width * height) / (1920 * 1080))

    ParticleSystem {
        id: sys
        running: root.running && root.visible
        paused: !(root.running && root.visible)
    }

    ImageParticle {
        system: sys
        source: "particle.svg"
        color: root.tint
        alpha: root.s.alpha
        alphaVariation: 0.3
        entryEffect: ImageParticle.Fade
        rotationVariation: root.kind === "rain" ? 0 : 180
        autoRotation: root.kind === "rain"
    }

    Emitter {
        system: sys
        width: root.width
        height: root.kind === "snow" || root.kind === "rain" ? 1 : root.height
        y: root.kind === "snow" || root.kind === "rain" ? -10 : 0
        emitRate: root.s.rate * root.density * root.areaScale
        lifeSpan: root.s.life
        lifeSpanVariation: root.s.life * 0.3
        size: root.s.size
        sizeVariation: root.s.sizeVar
        velocity: PointDirection {
            x: root.s.vx; y: root.s.vy
            xVariation: root.s.varX; yVariation: root.s.varY
        }
    }

    // Stars twinkle by drifting in and out of a slow turbulence field.
    Turbulence {
        system: sys
        anchors.fill: parent
        enabled: root.kind === "stars" || root.kind === "dust"
        strength: 6
    }
}
