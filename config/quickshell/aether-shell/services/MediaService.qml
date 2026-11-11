pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "../core"

// MPRIS media players.
//
// The active player is the one the user picked (selectPlayer), else the
// first one that is *playing*, else the first one — so a paused browser
// tab no longer hides the music player you're listening to.
//
// MPRIS doesn't push position updates; Quickshell exposes the value and
// asks clients to refresh it. `position` is re-read once a second, only
// while something is playing and a consumer has asked (wantPosition).
Singleton {
    id: root

    // Mpris.players is an ObjectModel; its array view is `.values`.
    readonly property var players: Mpris.players && Mpris.players.values ? Mpris.players.values : []
    property string pinnedIdentity: ""
    readonly property var primaryPlayer: {
        const list = root.players;
        if (list.length === 0) return null;
        if (root.pinnedIdentity.length) {
            const p = list.find(function(x) { return x.identity === root.pinnedIdentity; });
            if (p) return p;
        }
        return list.find(function(x) { return x.playbackState === MprisPlaybackState.Playing; }) || list[0];
    }
    readonly property bool available: primaryPlayer !== null
    readonly property bool playing: available && primaryPlayer.playbackState === MprisPlaybackState.Playing
    readonly property string title: available ? (primaryPlayer.trackTitle || "") : ""
    readonly property string artist: available ? (primaryPlayer.trackArtist || "") : ""
    readonly property string album: available ? (primaryPlayer.trackAlbum || "") : ""
    readonly property string artUrl: available ? (primaryPlayer.trackArtUrl || "") : ""
    readonly property string identity: available ? (primaryPlayer.identity || "") : ""
    readonly property bool canSeek: available && primaryPlayer.canSeek === true && primaryPlayer.positionSupported === true
    readonly property real length: available && primaryPlayer.lengthSupported ? primaryPlayer.length : 0
    property real position: 0
    readonly property bool volumeSupported: available && primaryPlayer.volumeSupported === true
    readonly property real volume: volumeSupported ? primaryPlayer.volume : 0

    property int positionConsumers: 0
    function wantPosition() { root.positionConsumers += 1; root._readPosition(); }
    function releasePosition() { root.positionConsumers = Math.max(0, root.positionConsumers - 1); }

    function _readPosition() {
        if (!root.available || !primaryPlayer.positionSupported) { root.position = 0; return; }
        root.position = primaryPlayer.position;
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.playing && root.positionConsumers > 0
        onTriggered: {
            if (typeof root.primaryPlayer.positionChanged === "function") root.primaryPlayer.positionChanged();
            root._readPosition();
        }
    }
    onPrimaryPlayerChanged: root._readPosition()

    function selectPlayer(identity) { root.pinnedIdentity = identity || ""; }

    function playPause() {
        if (available && primaryPlayer.canTogglePlaying) primaryPlayer.isPlaying = !primaryPlayer.isPlaying;
    }
    function next() { if (available && primaryPlayer.canGoNext) primaryPlayer.next(); }
    function previous() { if (available && primaryPlayer.canGoPrevious) primaryPlayer.previous(); }
    function seek(seconds) {
        if (!root.canSeek) return;
        primaryPlayer.position = Math.max(0, Math.min(root.length, seconds));
        root.position = primaryPlayer.position;
    }
    function setVolume(v) {
        if (root.volumeSupported && primaryPlayer.canControl) primaryPlayer.volume = Math.max(0, Math.min(1, v));
    }

    function formatTime(s) {
        if (!(s > 0)) return "0:00";
        const m = Math.floor(s / 60), r = Math.floor(s % 60);
        return m + ":" + (r < 10 ? "0" : "") + r;
    }
}
