import QtQuick
import "../theme"

// A translucent rounded surface. True backdrop blur comes from the
// compositor (Hyprland `layerrule = blur, <window class>`) — QML can't blur
// behind itself, so this only provides the tint/border/radius half of the
// "glass" look.
Rectangle {
    radius: Metrics.radiusMd
    color: Colors.withAlpha(Colors.glass, Colors.glassOpacity)
    border.width: Metrics.borderWidth
    border.color: Colors.border
}
