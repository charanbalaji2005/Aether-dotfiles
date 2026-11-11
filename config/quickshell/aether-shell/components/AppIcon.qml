import QtQuick
import Quickshell
import "../theme"

// Icon resolution, in order:
//   1. an absolute path, used directly;
//   2. the user's icon theme (Papirus, Adwaita, …) through Quickshell's
//      theme-aware icon provider — this is what makes icon packs apply;
//   3. hicolor/pixmaps by name (themes that lack the icon);
// then a letter avatar, an honest placeholder rather than a broken image.
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

        const list = [];
        // Quickshell.iconPath(name, true) returns "" when the theme lacks it.
        if (typeof Quickshell.iconPath === "function") {
            const themed = Quickshell.iconPath(name, true);
            if (themed && themed.length > 0) list.push(themed);
        }
        const sizes = ["scalable", "256x256", "128x128", "64x64", "48x48", "32x32"];
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
