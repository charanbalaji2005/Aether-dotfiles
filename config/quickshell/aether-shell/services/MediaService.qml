pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import "../core"

Singleton {
    id: root

    // First connected MPRIS player. Multi-player switching is a future
    // refinement (see PROGRESS.md) — most desktops only run one at a time.
    readonly property var primaryPlayer: Mpris.players.count > 0 ? Mpris.players.get(0) : null
    readonly property bool available: primaryPlayer !== null
    readonly property bool playing: available && primaryPlayer.playbackState === MprisPlaybackState.Playing
    readonly property string title: available ? primaryPlayer.trackTitle : ""
    readonly property string artist: available ? primaryPlayer.trackArtist : ""

    function playPause() {
        if (available && primaryPlayer.canTogglePlaying) {
            primaryPlayer.isPlaying = !primaryPlayer.isPlaying;
        }
    }

    function next() {
        if (available && primaryPlayer.canGoNext) primaryPlayer.next();
    }

    function previous() {
        if (available && primaryPlayer.canGoPrevious) primaryPlayer.previous();
    }
}
