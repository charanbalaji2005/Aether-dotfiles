import QtQuick
import "../theme"

// Best-effort icon resolution: tries an absolute path directly, otherwise
// walks common hicolor/pixmap locations by icon name. This is not a full
// implementation of the freedesktop icon theme spec (no theme index parsing,
// no proper inheritance chain) — it's a pragmatic fallback chain that covers
// most installed apps. Falls back to a letter avatar when nothing resolves,
// which is an honest placeholder rather than a fake/broken icon.
Item {
    id: root

    property string iconName: ""
    implicitWidth: 40
    implicitHeight: 40

    readonly property var _candidates: _buildCandidates(iconName)
    property int _candidateIndex: 0

    onIconNameChanged: _candidateIndex = 0

    function _buildCandidates(name) {
        if (!name || name.length === 0) return [];
        if (name.charAt(0) === "/") return ["file://" + name];

        const sizes = ["scalable", "256x256", "128x128", "64x64", "48x48", "32x32"];
        const list = [];
        for (const size of sizes) {
            const ext = size === "scalable" ? "svg" : "png";
            list.push("file:///usr/share/icons/hicolor/" + size + "/apps/" + name + "." + ext);
        }
        list.push("file:///usr/share/pixmaps/" + name + ".png");
        list.push("file:///usr/share/pixmaps/" + name + ".svg");
        return list;
    }

    Image {
        id: img
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
        visible: status === Image.Ready
        source: (root._candidates.length > root._candidateIndex) ? root._candidates[root._candidateIndex] : ""

        onStatusChanged: {
            if (status === Image.Error && root._candidateIndex < root._candidates.length - 1) {
                root._candidateIndex += 1;
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Metrics.radiusSm
        color: Colors.withAlpha(Colors.textMuted, 0.15)
        visible: img.status !== Image.Ready

        Text {
            anchors.centerIn: parent
            text: root.iconName.length > 0 ? root.iconName.charAt(0).toUpperCase() : "?"
            color: Colors.textSecondary
            font.family: Typography.family
            font.weight: Typography.weightSemibold
            font.pixelSize: parent.height * 0.4
        }
    }
}
