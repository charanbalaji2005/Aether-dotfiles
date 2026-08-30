pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire
import "../core"

Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool available: sink !== null

    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : true
    readonly property real inputVolume: source && source.audio ? source.audio.volume : 0
    readonly property bool inputMuted: source && source.audio ? source.audio.muted : true

    // Required for the node's live properties (volume/mute) to stay bound
    // and writable — see Quickshell.Services.Pipewire docs on PwObjectTracker.
    PwObjectTracker {
        objects: [root.sink, root.source].filter(function(n) { return n !== null; })
    }

    function setVolume(value) {
        if (!sink || !sink.audio) return;
        const clamped = Math.max(0, Math.min(1, value));
        sink.audio.muted = false;
        sink.audio.volume = clamped;
    }

    function adjustVolume(delta) {
        setVolume(volume + delta);
    }

    function toggleMute() {
        if (!sink || !sink.audio) return;
        sink.audio.muted = !sink.audio.muted;
    }

    function toggleInputMute() {
        if (!source || !source.audio) return;
        source.audio.muted = !source.audio.muted;
    }

    onVolumeChanged: EventBus.audioChanged(root.volume, root.muted)
    onMutedChanged: EventBus.audioChanged(root.volume, root.muted)
}
