import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Live thumbnail of one window. Loaded by Overview through a Loader with a
// *source URL*, so on a Quickshell build without ScreencopyView /
// Hyprland.toplevels this file fails to load and the Loader shows the icon
// fallback — the overview itself never breaks.
//
// Capture is one-shot (live: false) and refreshed on demand, so an open
// overview with twenty windows doesn't stream twenty video feeds.
Item {
    id: root

    property string address: ""
    property bool refreshTick: false
    readonly property bool ready: view.hasContent === true

    readonly property var toplevel: {
        const list = Hyprland.toplevels && Hyprland.toplevels.values ? Hyprland.toplevels.values : [];
        const want = root.address.replace(/^0x/, "");
        for (let i = 0; i < list.length; i++) {
            const a = String(list[i].address || "").replace(/^0x/, "");
            if (a === want) return list[i];
        }
        return null;
    }

    ScreencopyView {
        id: view
        anchors.fill: parent
        captureSource: root.toplevel && root.toplevel.wayland ? root.toplevel.wayland : null
        live: false
        constraintSize: Qt.size(root.width, root.height)
    }

    onRefreshTickChanged: if (typeof view.captureFrame === "function") view.captureFrame()
}
