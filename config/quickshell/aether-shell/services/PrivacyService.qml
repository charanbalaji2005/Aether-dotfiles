pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../core"

// Is anything recording you? Derived from PipeWire's own stream metadata:
// a node whose media.class is "Stream/Input/Audio" is an app capturing a
// microphone (or other source); "Stream/Input/Video" is an app capturing a
// camera through PipeWire (browsers, portals, OBS's PipeWire source).
//
// Limits, stated: apps that open /dev/video* directly (V4L2, bypassing
// PipeWire) are not visible here; neither are ALSA apps that bypass the
// PipeWire ALSA plugin. The island and bar say "PipeWire" for that reason.
// Event-driven: Pipewire.nodes is a live model, nothing is polled.
Singleton {
    id: root

    readonly property var _nodes: Pipewire.nodes && Pipewire.nodes.values ? Pipewire.nodes.values : []
    function _cls(n) {
        try { return n && n.properties ? (n.properties["media.class"] || "") : ""; } catch (e) { return ""; }
    }
    function _app(n) {
        try {
            const p = n.properties || {};
            return p["application.name"] || p["application.process.binary"] || p["node.name"] || "an app";
        } catch (e) { return "an app"; }
    }
    readonly property var micUsers: _nodes.filter(function(n) { return root._cls(n) === "Stream/Input/Audio"; }).map(root._app)
    readonly property var cameraUsers: _nodes.filter(function(n) { return root._cls(n) === "Stream/Input/Video"; }).map(root._app)
    readonly property bool micInUse: micUsers.length > 0
    readonly property bool cameraInUse: cameraUsers.length > 0
    readonly property bool screenShared: _nodes.some(function(n) { return root._cls(n) === "Video/Source" && /xdg-desktop-portal|screencast/i.test(root._app(n)); })

    // Node properties only arrive for bound nodes; bind the stream nodes.
    PwObjectTracker { objects: root._nodes.filter(function(n) { return n && n.isStream; }) }
}
