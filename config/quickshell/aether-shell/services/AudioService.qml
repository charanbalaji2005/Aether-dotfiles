pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../core"

// PipeWire audio: default output/input volume + mute, device lists, and
// switching the default device. Volume/mute go through Quickshell's live
// PipeWire bindings; switching defaults uses `wpctl set-default <id>`
// (WirePlumber's own CLI), which persists the choice like the GNOME/KDE
// mixers do.
Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool available: sink !== null
    readonly property bool inputAvailable: source !== null

    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : true
    readonly property real inputVolume: source && source.audio ? source.audio.volume : 0
    readonly property bool inputMuted: source && source.audio ? source.audio.muted : true

    // Hardware (non-stream) nodes only — application streams are excluded.
    readonly property var sinks: _nodes(true)
    readonly property var sources: _nodes(false)

    function _nodes(wantSink) {
        const all = Pipewire.nodes && Pipewire.nodes.values ? Pipewire.nodes.values : [];
        return all.filter(function(n) {
            return n && n.audio && !n.isStream && n.isSink === wantSink;
        });
    }

    function nodeLabel(n) {
        if (!n) return "";
        return n.description || n.nickname || n.name || ("Device " + n.id);
    }

    // Required for the nodes' live properties (volume/mute) to stay bound
    // and writable — see Quickshell.Services.Pipewire docs on PwObjectTracker.
    PwObjectTracker {
        objects: [root.sink, root.source].filter(function(n) { return n !== null; })
    }

    Process { id: wpctl }

    function setVolume(value) {
        if (!sink || !sink.audio) return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, value));
    }

    function adjustVolume(delta) {
        setVolume(volume + delta);
    }

    function toggleMute() {
        if (!sink || !sink.audio) return;
        sink.audio.muted = !sink.audio.muted;
    }

    function setInputVolume(value) {
        if (!source || !source.audio) return;
        source.audio.muted = false;
        source.audio.volume = Math.max(0, Math.min(1, value));
    }

    function toggleInputMute() {
        if (!source || !source.audio) return;
        source.audio.muted = !source.audio.muted;
    }

    function setDefault(node) {
        if (!node || node.id === undefined) return;
        wpctl.command = ["wpctl", "set-default", String(node.id)];
        wpctl.running = true;
        Logger.info("AudioService", "Default device -> " + root.nodeLabel(node));
    }

    onVolumeChanged: {
        EventBus.audioChanged(root.volume, root.muted);
        EventBus.osdRequested("volume", root.volume, root.muted);
    }
    onMutedChanged: {
        EventBus.audioChanged(root.volume, root.muted);
        EventBus.osdRequested("volume", root.volume, root.muted);
    }
    onInputMutedChanged: EventBus.osdRequested("microphone", root.inputVolume, root.inputMuted)
}
