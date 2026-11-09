import QtQuick
import "../theme"

// A translucent rounded surface. True backdrop blur comes from the
// compositor (Hyprland layerrule, see config/hypr/rules.conf) — QML can't
// blur behind itself, so this provides the tint, a soft vertical gradient,
// a hairline border and a top-edge highlight ("sheen").
Rectangle {
    id: root

    property real tintOpacity: Colors.glassOpacity
    property bool sheen: true

    radius: Metrics.radiusMd
    border.width: Metrics.borderWidth
    border.color: Colors.withAlpha(Colors.borderStrong, Colors.dark ? 0.75 : 0.9)

    gradient: Gradient {
        GradientStop { position: 0.0; color: Colors.withAlpha(Qt.lighter(Colors.glass, Colors.dark ? 1.18 : 1.0), root.tintOpacity) }
        GradientStop { position: 1.0; color: Colors.withAlpha(Colors.glass, root.tintOpacity) }
    }

    // 1px highlight along the top edge, inside the border.
    Rectangle {
        visible: root.sheen
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
