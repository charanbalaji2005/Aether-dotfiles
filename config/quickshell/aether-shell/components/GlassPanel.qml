import QtQuick
import "../theme"
import "../graphics"

// A translucent rounded surface — the AetherOS glass.
//
// Layers, back to front:
//   1. elevation shadow (stacked soft rings — no offscreen pass)
//   2. tint: vertical gradient at the glass preset's opacity
//   3. frost material (graphics/GlassMaterial: grain, pointer-following
//      specular, lit rim) — shader tiers only
//   4. hairline border, accent-tinted while `focused` (if enabled)
// True backdrop blur comes from the compositor (Hyprland layer rules) —
// QML can't blur what's behind its own window.
//
// The API is unchanged from earlier releases (it's still a Rectangle with
// radius/border/tintOpacity/sheen), so every existing surface upgrades
// without edits.
Rectangle {
    id: root

    property real tintOpacity: Colors.effectiveGlassOpacity
    property bool sheen: true
    property bool focused: false
    property bool accentBorder: true
    property int elevation: 2
    property bool material: true

    radius: Metrics.radiusMd
    border.width: Metrics.borderWidth
    border.color: focused && accentBorder
        ? Colors.withAlpha(Colors.accent, 0.55)
        : Colors.withAlpha(Colors.borderStrong, Colors.dark ? 0.75 : 0.9)
    Behavior on border.color { enabled: Motion.animate; ColorAnimation { duration: Motion.normal } }

    gradient: Gradient {
        GradientStop { position: 0.0; color: Colors.withAlpha(Qt.lighter(Colors.glass, Colors.dark ? 1.18 : 1.0), root.tintOpacity) }
        GradientStop { position: 1.0; color: Colors.withAlpha(Colors.glass, root.tintOpacity) }
    }

    // ── Elevation: three concentric rings of decreasing alpha ─────────
    Repeater {
        model: root.elevation > 0 && !Colors.highContrast ? 3 : 0
        delegate: Rectangle {
            required property int index
            readonly property real spread: Metrics.elevationBlur(root.elevation) * (index + 1) / 3
            z: -1
            x: -spread / 2
            y: -spread / 2 + Metrics.elevationOffset(root.elevation)
            width: root.width + spread
            height: root.height + spread
            radius: root.radius + spread / 2
            color: Colors.withAlpha(Colors.shadow, (Colors.dark ? 0.16 : 0.07) / (index + 1))
        }
    }

    GlassMaterial {
        anchors.fill: parent
        radius: root.radius
        visible: root.material
        pointer: hover.hovered ? Qt.point(hover.point.position.x / Math.max(1, root.width),
                                          hover.point.position.y / Math.max(1, root.height))
                               : Qt.point(0.5, 0.0)
        pointerInside: hover.hovered
    }

    // Passive: observes the pointer without stealing clicks from content.
    HoverHandler {
        id: hover
        enabled: root.material && Effects.lightFollow && !Effects.eco
    }

    // 1px highlight along the top edge, inside the border (non-shader tiers;
    // the material draws its own rim).
    Rectangle {
        visible: root.sheen && (Effects.eco || !ShaderLibrary.usable("glass"))
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Metrics.borderWidth
        anchors.leftMargin: root.radius * 0.6
        anchors.rightMargin: root.radius * 0.6
        height: 1
        color: Colors.highlight
    }
}
