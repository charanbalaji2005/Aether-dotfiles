pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import "../core"

Singleton {
    id: root

    // First connected MPRIS player. Multi-player switching is a future
    // refinement (see PROGRESS.md) — most desktops only run one at a time.
    // Mpris.players is an ObjectModel; its array view is `.values`.
    readonly property var _players: Mpris.players && Mpris.players.values ? Mpris.players.values : []
    readonly property var primaryPlayer: _players.length > 0 ? _players[0] : null
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
