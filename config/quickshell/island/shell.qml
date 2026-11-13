//@ pragma Env QS_NO_RELOAD_POPUP=1
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

// AetherOS Dynamic Island — a black capsule at the top centre, over the empty
// middle of Waybar's "home" bar. Waybar draws everything else.
//
//   idle            closed: the capsule shrinks away and is gone (and clicks
//                   pass through); Waybar keeps the date and time on the right
//   playing         art · title · live waveform (cava, tinted from the art)
//   paused          art · title · pause glyph, a little narrower
//   volume/bright.  a level bar for ~2 s (aether-osd → aether-island show-osd)
//   recording       red dot · elapsed time while aether-record runs (click: stop)
//   power events    charger plugged / unplugged, battery low (3 s)
//   open (click)    art, title, artist, waveform, seekable progress with
//                   elapsed / remaining time, previous · play/pause · next
//                   (with nothing playing: the time and date)
//   art (click)     a full-screen player; Esc, a click outside or ✕ closes it
//
// It peeks open for a few seconds when the track changes, closes 6 s after the
// pointer leaves; it hides over a fullscreen (not maximized) window. Media comes straight
// from MPRIS over D-Bus (no polling); position is read once a second only while
// open and playing; cava runs only while something plays. Album art is cached by
// ~/.config/waybar/scripts/media-artwork.sh. Started by dynamic-island.sh.
ShellRoot {
    id: root

    // ── look ─────────────────────────────────────────────────────────────
    readonly property color bg: "#030304"
    readonly property color bgHover: "#0e0e11"
    readonly property color fg: "#f5f5f7"
    readonly property color fg2: Qt.rgba(0.96, 0.96, 0.97, 0.60)
    readonly property color fg3: Qt.rgba(1, 1, 1, 0.22)
    readonly property color blue: "#0a84ff"
    readonly property string font: pickFont(["SF Pro Display", "SF Pro Text", "Inter", "Inter Variable", "Noto Sans", "Cantarell"], "sans-serif")
    readonly property string iconFont: pickFont(["JetBrainsMono Nerd Font", "Symbols Nerd Font", "JetBrainsMono NF"], "monospace")
    readonly property int pillTop: 8   // centred on Waybar's 35 px bar (margin-top 6)
    readonly property bool peekOnTrackChange: true

    readonly property string gPrev: String.fromCodePoint(0xF04AE)
    readonly property string gNext: String.fromCodePoint(0xF04AD)
    readonly property string gPlay: String.fromCodePoint(0xF040A)
    readonly property string gPause: String.fromCodePoint(0xF03E4)
    readonly property string gNote: String.fromCodePoint(0xF0386)

    function pickFont(list, fallback) {
        const have = Qt.fontFamilies();
        for (let i = 0; i < list.length; i++) if (have.indexOf(list[i]) >= 0) return list[i];
        return fallback;
    }
    function fmt(s) {
        if (!(s > 0)) return "0:00";
        s = Math.floor(s);
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), r = s % 60;
        return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (r < 10 ? "0" : "") + r;
    }

    readonly property string home: Quickshell.env("HOME")
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/aether/island"
    readonly property string scripts: home + "/.config/waybar/scripts"

    // ── player choice: the one playing, else the one that played last ────
    readonly property var players: Mpris.players ? Mpris.players.values : []
    property var sticky: null
    readonly property var playingPlayer: {
        const l = root.players;
        for (let i = 0; i < l.length; i++) if (l[i].playbackState === MprisPlaybackState.Playing) return l[i];
        return null;
    }
    onPlayingPlayerChanged: if (playingPlayer) sticky = playingPlayer
    readonly property var player: {
        if (root.playingPlayer) return root.playingPlayer;
        const l = root.players;
        if (root.sticky && l.indexOf(root.sticky) >= 0 && root.sticky.trackTitle) return root.sticky;
        for (let i = 0; i < l.length; i++)
            if (l[i].trackTitle && l[i].playbackState === MprisPlaybackState.Paused) return l[i];
        return null;
    }
    readonly property bool hasMedia: player !== null && (player.trackTitle || "") !== ""
    readonly property bool playing: hasMedia && player.playbackState === MprisPlaybackState.Playing
    readonly property string title: hasMedia ? player.trackTitle : ""
    readonly property string artist: hasMedia ? (player.trackArtist || player.identity || "") : ""
    readonly property string artUrl: hasMedia ? (player.trackArtUrl || "") : ""
    // Position and length are asked from the player itself (playerctl) once a
    // second while the timeline is on screen: Quickshell extrapolates position
    // from the last value it was sent, which drifts after seeks and track
    // changes in browsers. Its own values are only the fallback.
    readonly property string busName: hasMedia ? (player.dbusName || "").replace(/^org\.mpris\.MediaPlayer2\./, "") : ""
    property real queriedLength: 0
    readonly property real length: queriedLength > 0 ? queriedLength
        : hasMedia && player.lengthSupported && player.length > 0 ? player.length : 0
    readonly property bool canSeek: hasMedia && player.canSeek && length > 0
    property real position: 0
    property bool smoothProgress: false

    function setPosition(p) {
        root.smoothProgress = root.playing && Math.abs(p - root.position) < 2.5;
        root.position = p;
    }
    // Browsers report a new position only on seeks and track changes and keep
    // the old value meanwhile. A reported value that moved is the truth (seek,
    // new track); one that sat still while playing is advanced by the clock.
    property real lastReported: -1
    property double lastReportAt: 0
    function takeReported(p) {
        const now = Date.now();
        const moved = root.lastReported < 0 || Math.abs(p - root.lastReported) >= 0.05;
        let pos = root.position;
        if (moved) pos = p;
        else if (root.playing && root.lastReportAt > 0) pos = root.position + (now - root.lastReportAt) / 1000;
        root.lastReported = p;
        root.lastReportAt = now;
        root.setPosition(root.length > 0 ? Math.min(pos, root.length) : pos);
    }
    function readPosition() {
        if (!root.hasMedia) { root.position = 0; root.queriedLength = 0; return; }
        if (root.busName && !posProc.running) {
            posProc.command = ["sh", "-c",
                "p=$(playerctl -p \"$1\" position 2>/dev/null); l=$(playerctl -p \"$1\" metadata mpris:length 2>/dev/null); echo \"$p|$l\"",
                "sh", root.busName];
            posProc.running = true;
        } else if (!root.busName && root.player.positionSupported) {
            root.setPosition(root.player.position);
        }
    }
    Process {
        id: posProc
        stdout: StdioCollector {
            onStreamFinished: {
                const f = this.text.trim().split("|");
                const p = parseFloat(f[0]), l = parseInt(f[1]);
                root.queriedLength = l > 0 ? l / 1000000 : 0;
                if (p >= 0) root.takeReported(p);
                else if (root.hasMedia && root.player.positionSupported) root.setPosition(root.player.position);
            }
        }
    }
    function seekTo(fraction) {
        if (!root.canSeek) return;
        const t = Math.max(0, Math.min(root.length - 1, fraction * root.length));
        root.smoothProgress = false;
        root.position = t;
        if (root.busName) Quickshell.execDetached(["playerctl", "-p", root.busName, "position", t.toFixed(2)]);
        else root.player.position = t;
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.playing && (root.open || root.showPlayer)
        triggeredOnStart: true
        onTriggered: root.readPosition()
    }

    // ── open / peek / collapse ───────────────────────────────────────────
    property bool expanded: false
    property bool showPlayer: false      // the full-screen player
    property bool peeking: false
    property int hoverCount: 0          // pointer over the island on any screen
    readonly property bool hovered: hoverCount > 0
    readonly property bool open: expanded || peeking
    property bool settled: false
    Timer { interval: 2500; running: true; onTriggered: root.settled = true }

    onTitleChanged: {
        root.queriedLength = 0;
        root.lastReported = -1;
        root.lastReportAt = 0;
        root.pausedStale = false;
        root.smoothProgress = false;
        root.readPosition();
        if (root.settled && root.peekOnTrackChange && root.playing && !root.expanded && root.title !== "") {
            root.peeking = true;
            peekTimer.restart();
        }
    }
    onHasMediaChanged: if (!hasMedia) { peeking = false; showPlayer = false; }
    // Read the position on opening too, so a paused track shows where it stopped.
    onOpenChanged: if (open) readPosition()
    onShowPlayerChanged: if (showPlayer) readPosition()
    onPlayingChanged: {
        // Count up to the moment of pausing; don't count the paused time.
        if (lastReportAt > 0) {
            const now = Date.now();
            if (!playing) position = position + (now - lastReportAt) / 1000;
            lastReportAt = now;
        }
        readPosition();
        pausedStale = false;
    }

    // A paused track keeps the island for pausedLinger ms, then it closes
    // (a paused browser tab would otherwise hold it open for ever).
    readonly property int pausedLinger: 30000
    property bool pausedStale: false
    Timer {
        interval: root.pausedLinger
        running: root.hasMedia && !root.playing && !root.pausedStale
        onTriggered: root.pausedStale = true
    }
    Timer { id: peekTimer; interval: 3800; onTriggered: if (root.hovered) restart(); else root.peeking = false }
    Timer { interval: 6000; running: root.expanded && !root.hovered; onTriggered: root.expanded = false }

    function toggle() {
        if (root.peeking) { root.peeking = false; root.expanded = true; return; }
        root.expanded = !root.expanded;
    }

    // ── volume / brightness level (written by aether-island show-osd) ────
    property bool osdActive: false
    property string osdIcon: ""
    property int osdPct: 0
    property string osdLabel: ""
    function parseOsd(t) {
        const f = (t || "").trim().split("|");
        if (f.length < 4) return;
        const left = parseInt(f[0]) - Date.now();
        if (!(left > 0)) return;
        root.osdIcon = f[1]; root.osdPct = Math.max(0, Math.min(100, parseInt(f[2]) || 0)); root.osdLabel = f[3];
        root.osdActive = true;
        osdTimer.interval = Math.min(left, 4000);
        osdTimer.restart();
    }
    Timer { id: osdTimer; onTriggered: root.osdActive = false }
    FileView {
        path: root.cacheDir + "/osd"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parseOsd(text())
    }

    // ── 12/24 h clock from the classic interface state ───────────────────
    property bool clock12: false
    FileView {
        path: root.home + "/.config/aether-shell/classic/state.conf"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.clock12 = /^island_clock=12$/m.test(text())
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }

    readonly property string mode: osdActive && !expanded ? "osd"
        : eventActive && !expanded ? "event"
        : open ? (hasMedia ? "media" : "clock")
        : recording ? "rec"
        : hasMedia && (playing || !pausedStale) ? (playing ? "live" : "paused") : "idle"

    // ── album art: cached locally, accent colour taken from it ───────────
    property string artPath: ""
    onArtUrlChanged: fetchArt()
    function fetchArt() {
        if (!root.artUrl) { root.artPath = ""; return; }
        artProc.running = false;
        artProc.command = [root.scripts + "/media-artwork.sh", root.artUrl];
        artProc.running = true;
    }
    Process {
        id: artProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (artProc.command[1] !== root.artUrl) return;   // a newer track won
                const p = this.text.trim();
                if (p) root.artPath = "file://" + p;
                else if (/^(https?|file):/.test(root.artUrl)) root.artPath = root.artUrl;
                else root.artPath = "";
            }
        }
    }
    ColorQuantizer { id: quant; source: root.artPath; depth: 2; rescaleSize: 48 }
    readonly property color accent: {
        const cs = quant.colors || [];
        let best = null, score = 0.12;
        for (let i = 0; i < cs.length; i++) {
            const s = cs[i].hsvSaturation * cs[i].hsvValue;
            if (s > score) { score = s; best = cs[i]; }
        }
        if (!best) return root.blue;
        return Qt.hsva(best.hsvHue, Math.min(1, best.hsvSaturation * 1.1), Math.max(0.78, best.hsvValue), 1);
    }

    // ── waveform levels: cava on what you hear, only while playing ───────
    readonly property int nBars: 6
    property var levels: [0, 0, 0, 0, 0, 0]
    property bool cavaOk: false
    readonly property string cavaConf: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/aether-island-cava.conf"
    readonly property string cavaText: [
        "[general]", "bars = " + root.nBars, "framerate = 30", "autosens = 1",
        "lower_cutoff_freq = 50", "higher_cutoff_freq = 10000",
        "[input]", "method = pipewire", "source = auto",
        "[output]", "method = raw", "raw_target = /dev/stdout", "data_format = ascii",
        "ascii_max_range = 100", "bar_delimiter = 59", "frame_delimiter = 10",
        "[smoothing]", "noise_reduction = 55"
    ].join("\n") + "\n"
    Process {
        running: true
        command: ["sh", "-c", "command -v cava >/dev/null && printf '%s' \"$1\" > \"$2\"", "sh", root.cavaText, root.cavaConf]
        onExited: function(code) { root.cavaOk = code === 0; }
    }
    Process {
        id: cava
        running: root.cavaOk && root.playing
        command: ["cava", "-p", root.cavaConf]
        stdout: SplitParser {
            onRead: function(line) {
                const parts = line.split(";");
                if (parts.length < root.nBars) return;
                const out = new Array(root.nBars);
                for (let i = 0; i < root.nBars; i++) out[i] = Math.min(1, (parseInt(parts[i]) || 0) / 100);
                root.levels = out;
            }
        }
        onRunningChanged: if (!running) root.levels = [0, 0, 0, 0, 0, 0]
    }
    // Without cava: a gentle synthetic motion so "playing" still reads at a glance.
    Timer {
        interval: 180
        repeat: true
        running: !root.cavaOk && root.playing
        onTriggered: {
            const out = new Array(root.nBars);
            for (let i = 0; i < root.nBars; i++) out[i] = 0.25 + Math.random() * 0.7;
            root.levels = out;
        }
    }


    // ── task: screen recording (aether-record's PID file, watched by inotify) ──
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    property bool recording: false
    property double recSince: 0
    property int recSeconds: 0
    onRecordingChanged: { recSince = Date.now(); recSeconds = 0; }
    Process {
        running: true
        command: ["sh", "-c", "test -s \"$1/aether-record.pid\" && echo on; exec inotifywait -mq -e create,close_write,delete,moved_to,moved_from --format '%e %f' \"$1\"", "sh", root.runtimeDir]
        stdout: SplitParser {
            onRead: function(line) {
                if (line === "on") { root.recording = true; return; }
                if (!/ aether-record\.pid$/.test(line)) return;
                root.recording = !/^(DELETE|MOVED_FROM)/.test(line);
            }
        }
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.recording
        onTriggered: root.recSeconds = Math.floor((Date.now() - root.recSince) / 1000)
    }
    Process { id: recStop; command: ["aether-record", "stop"] }

    // ── task: power events (UPower) ──────────────────────────────────────
    property bool eventActive: false
    property string eventIcon: ""
    property string eventText: ""
    property color eventColor: root.fg
    function showEvent(icon, text, color) {
        root.eventIcon = icon; root.eventText = text; root.eventColor = color;
        root.eventActive = true;
        eventTimer.restart();
    }
    Timer { id: eventTimer; interval: 3000; onTriggered: root.eventActive = false }
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.isLaptopBattery === true
    readonly property int batteryPct: {
        if (!hasBattery) return 0;
        const p = battery.percentage;
        return Math.round(p <= 1.0 ? p * 100 : p);
    }
    readonly property bool onBattery: UPower.onBattery
    property bool lowWarned: false
    onOnBatteryChanged: {
        if (!root.settled || !root.hasBattery) return;
        if (root.onBattery) root.showEvent(String.fromCodePoint(0xF0083), "On battery  ·  " + root.batteryPct + "%", root.fg);
        else root.showEvent(String.fromCodePoint(0xF0084), "Charging  ·  " + root.batteryPct + "%", "#30d158");
    }
    onBatteryPctChanged: {
        if (!root.hasBattery) return;
        if (root.onBattery && root.batteryPct <= 15 && !root.lowWarned) {
            root.lowWarned = true;
            root.showEvent(String.fromCodePoint(0xF007A), "Battery low  ·  " + root.batteryPct + "%", "#ff453a");
        } else if (root.batteryPct > 20) root.lowWarned = false;
    }

    // ── true fullscreen (mode 2/3; 1 is "maximized") on the focused window ──
    property int fsMonitorId: -1
    Process {
        id: fsProc
        running: true
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const w = JSON.parse(this.text);
                    root.fsMonitorId = (w && w.fullscreen >= 2) ? w.monitor : -1;
                } catch (e) { root.fsMonitorId = -1; }
            }
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = event.name;
            if (n === "fullscreen" || n === "activewindowv2" || n === "workspacev2" || n === "closewindow"
                || n === "focusedmonv2" || n === "movewindowv2") {
                fsProc.running = false;
                fsProc.running = true;
            }
        }
    }

    IpcHandler {
        target: "island"
        function toggle(): void { root.toggle(); }
        function expand(): void { root.peeking = false; root.expanded = true; }
        function collapse(): void { root.peeking = false; root.expanded = false; }
        function player(): void { if (root.hasMedia) root.showPlayer = !root.showPlayer; }
        function peek(): void { if (root.hasMedia) { root.peeking = true; peekTimer.restart(); } }
        function info(): string {
            return JSON.stringify({ mode: root.mode, player: root.hasMedia ? root.player.identity : "", playing: root.playing,
                title: root.title, artist: root.artist, position: Math.round(root.position), length: root.length,
                lengthSupported: root.hasMedia ? root.player.lengthSupported : false, canSeek: root.canSeek,
                art: root.artPath, accent: root.accent.toString(), cava: root.cavaOk && cava.running, font: root.font,
                recording: root.recording });
        }
    }

    // ── reusable bits ────────────────────────────────────────────────────
    component Wave: Row {
        id: wave
        property real maxH: 16
        property real barW: 3
        property color tint: root.accent
        spacing: Math.round(barW * 0.75)
        height: maxH
        Repeater {
            model: root.nBars
            Rectangle {
                required property int index
                anchors.verticalCenter: parent.verticalCenter
                width: wave.barW
                radius: width / 2
                color: wave.tint
                // Outer bars a little lower, like the iOS live activity.
                readonly property real shape: [0.62, 0.86, 1, 1, 0.86, 0.62][index] || 1
                height: Math.max(wave.barW, wave.maxH * (root.playing ? Math.max(0.14, Math.min(1, root.levels[index] || 0)) * shape : 0))
                Behavior on height { NumberAnimation { duration: 95; easing.type: Easing.OutQuad } }
                Behavior on color { ColorAnimation { duration: 400 } }
            }
        }
    }

    component IconButton: Item {
        id: btn
        property string glyph: ""
        property real size: 20
        property bool active: true
        signal clicked()
        width: size * 2
        height: size * 2
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.rgba(1, 1, 1, !btn.active ? 0 : ma.pressed ? 0.18 : ma.containsMouse ? 0.10 : 0)
            Behavior on color { ColorAnimation { duration: 140 } }
        }
        Text {
            anchors.centerIn: parent
            text: btn.glyph
            font.family: root.iconFont
            font.pixelSize: btn.size
            color: btn.active ? root.fg : root.fg3
            scale: ma.pressed ? 0.86 : 1
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.active) btn.clicked()
        }
    }

    component Art: ClippingRectangle {
        id: art
        property real size: 22
        property bool opensPlayer: true
        width: size
        height: size
        radius: Math.round(size * 0.24)
        color: Qt.rgba(1, 1, 1, 0.08)
        Text {
            anchors.centerIn: parent
            visible: img.status !== Image.Ready
            text: root.gNote
            font.family: root.iconFont
            font.pixelSize: art.size * 0.5
            color: root.fg2
        }
        Image {
            id: img
            anchors.fill: parent
            source: root.artPath
            sourceSize: Qt.size(256, 256)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            mipmap: true
            opacity: status === Image.Ready ? (root.playing ? 1 : 0.55) : 0
            Behavior on opacity { NumberAnimation { duration: 260 } }
        }
        MouseArea {
            anchors.fill: parent
            enabled: art.opensPlayer && root.hasMedia
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.showPlayer = true; root.peeking = false; root.expanded = false; }
        }
    }

    // elapsed · seekable bar · remaining
    component Progress: Item {
        id: prog
        property real barH: 5
        property real fontSize: 11
        height: Math.max(16, barH * 3)
        Text {
            id: elapsed
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: prog.fontSize * 3.8
            text: root.fmt(root.position)
            font.family: root.font
            font.pixelSize: prog.fontSize
            font.features: { "tnum": 1 }
            color: root.fg2
        }
        Item {
            id: track
            anchors.left: elapsed.right
            anchors.right: remaining.left
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            readonly property bool hot: seekArea.containsMouse || seekArea.pressed
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: track.hot ? prog.barH + 2 : prog.barH
                radius: height / 2
                color: root.fg3
                Behavior on height { NumberAnimation { duration: 120 } }
                // No length from the player (live streams, some browser videos):
                // a slow sweep instead of an empty bar; elapsed time still counts.
                Rectangle {
                    id: sweep
                    visible: root.length <= 0 && root.hasMedia
                    width: parent.width * 0.18
                    height: parent.height
                    radius: parent.radius
                    color: Qt.rgba(1, 1, 1, 0.55)
                    SequentialAnimation on x {
                        running: sweep.visible && root.playing && prog.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 0; to: sweep.parent.width - sweep.width; duration: 1600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0; duration: 1600; easing.type: Easing.InOutSine }
                    }
                }
                Rectangle {
                    width: root.length > 0 ? parent.width * Math.min(1, root.position / root.length) : 0
                    height: parent.height
                    radius: parent.radius
                    color: track.hot ? root.fg : Qt.rgba(1, 1, 1, 0.85)
                    Behavior on width {
                        enabled: root.smoothProgress
                        NumberAnimation { duration: 1000; easing.type: Easing.Linear }
                    }
                }
            }
            MouseArea {
                id: seekArea
                anchors.fill: parent
                enabled: root.canSeek
                hoverEnabled: true
                cursorShape: root.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: function(ev) { root.seekTo(ev.x / width); }
            }
        }
        Text {
            id: remaining
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: prog.fontSize * 3.8
            horizontalAlignment: Text.AlignRight
            text: root.length > 0 ? "-" + root.fmt(Math.max(0, root.length - root.position)) : "LIVE"
            font.family: root.font
            font.pixelSize: prog.fontSize
            font.features: { "tnum": 1 }
            color: root.fg2
        }
    }

    // A layer that fades in once the capsule has grown to fit it.
    component Layer: Item {
        property bool shown: false
        opacity: shown ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
    }

    // ── the island, one per monitor ──────────────────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData


            anchors.top: true
            implicitWidth: 560
            implicitHeight: 236
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            // Above Waybar whatever order they start in; hidden over a truly
            // fullscreen window (see fsMonitorId), not over maximized ones.
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "aether-island"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // Only the capsule takes input; the rest of the surface clicks through.
            readonly property var hyprMon: Hyprland.monitorFor(modelData)
            readonly property bool fullscreen: root.fsMonitorId >= 0 && hyprMon !== null && hyprMon.id === root.fsMonitorId
            readonly property bool hidden: root.mode === "idle" || fullscreen
            mask: Region { item: win.hidden ? null : pill }

            readonly property bool compact: root.mode !== "media" && root.mode !== "clock"
            readonly property size target: {
                switch (root.mode) {
                case "media": return Qt.size(468, 186);
                case "clock": return Qt.size(300, 84);
                case "osd": return Qt.size(286, 32);
                case "event": return Qt.size(270, 32);
                case "rec": return Qt.size(200, 32);
                case "idle": return Qt.size(72, 20);   // shrinks to this as it fades out
                case "live": return Qt.size(316, 32);
                case "paused": return Qt.size(262, 32);
                default: return Qt.size(132, 32);
                }
            }
            readonly property bool hot: hover.hovered

            Item {
                id: pill
                x: Math.round((win.width - width) / 2)
                y: root.pillTop
                width: win.target.width + (win.compact && win.hot ? 16 : 0)
                height: win.target.height + (win.compact && win.hot ? 2 : 0)
                opacity: win.hidden ? 0 : 1
                scale: win.hidden ? 0.7 : 1
                transformOrigin: Item.Top
                Behavior on opacity { NumberAnimation { duration: win.hidden ? 260 : 160; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on width { SpringAnimation { spring: 3.6; damping: 0.34; epsilon: 0.25 } }
                Behavior on height { SpringAnimation { spring: 3.6; damping: 0.38; epsilon: 0.25 } }

                HoverHandler {
                    id: hover
                    onHoveredChanged: root.hoverCount += hovered ? 1 : -1
                }

                ClippingRectangle {
                    id: body
                    anchors.fill: parent
                    radius: win.compact ? height / 2 : 40
                    color: win.hot ? root.bgHover : root.bg
                    Behavior on radius { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 160 } }

                    // Background click: open / close. Buttons sit above it.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function(ev) {
                            if (ev.button === Qt.MiddleButton) { if (root.hasMedia && root.player.canTogglePlaying) root.player.togglePlaying(); }
                            else if (ev.button === Qt.RightButton) { if (root.hasMedia && root.player.canRaise) root.player.raise(); }
                            else root.toggle();
                        }
                        onWheel: function(ev) {
                            if (!root.hasMedia) return;
                            if (ev.angleDelta.y > 0 && root.player.canGoPrevious) root.player.previous();
                            else if (ev.angleDelta.y < 0 && root.player.canGoNext) root.player.next();
                        }
                    }

                    // playing / paused: art · title · waveform
                    Layer {
                        shown: root.mode === "live" || root.mode === "paused"
                        width: win.target.width
                        height: 32
                        anchors.centerIn: parent
                        Art {
                            id: miniArt
                            size: 22
                            anchors.left: parent.left
                            anchors.leftMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            anchors.left: miniArt.right
                            anchors.leftMargin: 10
                            anchors.right: miniRight.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.title
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            font.family: root.font
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: root.playing ? root.fg : root.fg2
                        }
                        Item {
                            id: miniRight
                            width: 30
                            height: parent.height
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            Wave {
                                anchors.centerIn: parent
                                visible: root.playing
                                maxH: 15
                                barW: 3
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !root.playing
                                text: root.gPause
                                font.family: root.iconFont
                                font.pixelSize: 15
                                color: root.fg2
                            }
                        }
                    }

                    // recording: red dot · elapsed · stop
                    Layer {
                        shown: root.mode === "rec"
                        width: win.target.width
                        height: 32
                        anchors.centerIn: parent
                        Rectangle {
                            id: recDot
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 10; height: 10; radius: 5
                            color: "#ff453a"
                            SequentialAnimation on opacity {
                                running: root.mode === "rec"
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                            }
                        }
                        Text {
                            anchors.left: recDot.right
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: "REC  " + root.fmt(root.recSeconds)
                            font.family: root.font
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: root.fg
                        }
                        IconButton {
                            anchors.right: parent.right
                            anchors.rightMargin: 2
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: String.fromCodePoint(0xF04DB)   // stop
                            size: 14
                            onClicked: recStop.running = true
                        }
                    }

                    // charger / battery notice
                    Layer {
                        shown: root.mode === "event"
                        width: win.target.width
                        height: 32
                        anchors.centerIn: parent
                        Row {
                            anchors.centerIn: parent
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.eventIcon
                                font.family: root.iconFont
                                font.pixelSize: 16
                                color: root.eventColor
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.eventText
                                font.family: root.font
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: root.fg
                            }
                        }
                    }

                    // volume / brightness level
                    Layer {
                        shown: root.mode === "osd"
                        width: win.target.width
                        height: 32
                        anchors.centerIn: parent
                        Text {
                            id: osdGlyph
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.osdIcon
                            font.family: root.iconFont
                            font.pixelSize: 15
                            color: root.fg
                        }
                        Rectangle {
                            id: osdTrack
                            anchors.left: osdGlyph.right
                            anchors.leftMargin: 12
                            anchors.right: osdNum.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            height: 5
                            radius: 3
                            color: root.fg3
                            Rectangle {
                                width: parent.width * root.osdPct / 100
                                height: parent.height
                                radius: parent.radius
                                color: root.fg
                                Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            }
                        }
                        Text {
                            id: osdNum
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            horizontalAlignment: Text.AlignRight
                            text: root.osdPct
                            font.family: root.font
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: root.fg2
                        }
                    }

                    // open, nothing playing: time and date
                    Layer {
                        shown: root.mode === "clock"
                        width: 300
                        height: 84
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.formatDateTime(clock.date, root.clock12 ? "h:mm AP" : "HH:mm")
                                font.family: root.font
                                font.pixelSize: 30
                                font.weight: Font.DemiBold
                                font.features: { "tnum": 1 }
                                color: root.fg
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.formatDateTime(clock.date, "dddd, d MMMM") + "  ·  Nothing playing"
                                font.family: root.font
                                font.pixelSize: 12
                                color: root.fg2
                            }
                        }
                    }

                    // open, with media: the full player
                    Layer {
                        id: full
                        shown: root.mode === "media"
                        width: 468
                        height: 186
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top

                        Art {
                            id: bigArt
                            size: 64
                            x: 20
                            y: 20
                        }
                        Column {
                            anchors.left: bigArt.right
                            anchors.leftMargin: 14
                            anchors.right: bigWave.left
                            anchors.rightMargin: 14
                            anchors.verticalCenter: bigArt.verticalCenter
                            spacing: 3
                            Text {
                                width: parent.width
                                text: root.title
                                elide: Text.ElideRight
                                font.family: root.font
                                font.pixelSize: 15
                                font.weight: Font.DemiBold
                                color: root.fg
                            }
                            Text {
                                width: parent.width
                                text: root.artist
                                elide: Text.ElideRight
                                font.family: root.font
                                font.pixelSize: 13
                                color: root.fg2
                            }
                        }
                        Item {
                            id: bigWave
                            width: 40
                            height: 64
                            anchors.right: parent.right
                            anchors.rightMargin: 22
                            anchors.verticalCenter: bigArt.verticalCenter
                            Wave {
                                anchors.centerIn: parent
                                maxH: 24
                                barW: 4
                                opacity: root.playing ? 1 : 0.35
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }
                        }

                        Progress {
                            x: 20
                            y: 100
                            width: parent.width - 40
                        }

                        // controls
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 126
                            spacing: 26
                            IconButton {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: root.gPrev
                                size: 20
                                active: root.hasMedia && root.player.canGoPrevious
                                onClicked: root.player.previous()
                            }
                            IconButton {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: root.playing ? root.gPause : root.gPlay
                                size: 26
                                active: root.hasMedia && root.player.canTogglePlaying
                                onClicked: root.player.togglePlaying()
                            }
                            IconButton {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: root.gNext
                                size: 20
                                active: root.hasMedia && root.player.canGoNext
                                onClicked: root.player.next()
                            }
                        }
                    }
                }
            }
        }
    }

    // ── full-screen player (click the album art) ─────────────────────────
    LazyLoader {
        active: root.showPlayer

        PanelWindow {
            id: fsp
            screen: {
                const fm = Hyprland.focusedMonitor;
                const ss = Quickshell.screens;
                for (let i = 0; i < ss.length; i++) if (fm && ss[i].name === fm.name) return ss[i];
                return ss.length > 0 ? ss[0] : null;
            }
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "aether-island-player"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Item {
                id: stage
                anchors.fill: parent
                focus: true
                opacity: 0
                Component.onCompleted: { opacity = 1; heroScale.scale = 1; }
                Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Keys.onPressed: function(ev) {
                    if (ev.key === Qt.Key_Escape || ev.key === Qt.Key_Q) root.showPlayer = false;
                    else if (ev.key === Qt.Key_Space && root.player.canTogglePlaying) root.player.togglePlaying();
                    else if (ev.key === Qt.Key_Right && root.canSeek) root.seekTo((root.position + 10) / root.length);
                    else if (ev.key === Qt.Key_Left && root.canSeek) root.seekTo(Math.max(0, root.position - 10) / root.length);
                    else if (ev.key === Qt.Key_N && root.player.canGoNext) root.player.next();
                    else if (ev.key === Qt.Key_P && root.player.canGoPrevious) root.player.previous();
                    ev.accepted = true;
                }

                // Backdrop: the album art, heavily blurred and darkened.
                Rectangle { anchors.fill: parent; color: "#000000" }
                Image {
                    anchors.fill: parent
                    id: backdrop
                    source: root.artPath
                    sourceSize: Qt.size(48, 48)     // tiny on purpose: upscaled + blurred = soft colour wash
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: backdrop
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 64
                    saturation: 0.35
                    brightness: -0.3
                    visible: backdrop.status === Image.Ready
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.35) }
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.75) }
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: root.showPlayer = false }

                Column {
                    id: heroScale
                    anchors.centerIn: parent
                    spacing: 0
                    scale: 0.92
                    Behavior on scale { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                    readonly property real artSize: Math.min(420, fsp.height * 0.42)

                    Art {
                        anchors.horizontalCenter: parent.horizontalCenter
                        size: heroScale.artSize
                        opensPlayer: false
                        scale: root.playing ? 1 : 0.9
                        Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                    }
                    Item { width: 1; height: 34 }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(fsp.width * 0.8, 640)
                        horizontalAlignment: Text.AlignHCenter
                        text: root.title
                        elide: Text.ElideRight
                        font.family: root.font
                        font.pixelSize: 28
                        font.weight: Font.Bold
                        color: root.fg
                    }
                    Item { width: 1; height: 6 }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(fsp.width * 0.8, 640)
                        horizontalAlignment: Text.AlignHCenter
                        text: root.artist
                        elide: Text.ElideRight
                        font.family: root.font
                        font.pixelSize: 18
                        color: root.fg2
                    }
                    Item { width: 1; height: 30 }
                    Progress {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(fsp.width * 0.8, 560)
                        barH: 6
                        fontSize: 13
                    }
                    Item { width: 1; height: 18 }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 44
                        IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: root.gPrev; size: 30
                            active: root.hasMedia && root.player.canGoPrevious
                            onClicked: root.player.previous()
                        }
                        IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: root.playing ? root.gPause : root.gPlay; size: 42
                            active: root.hasMedia && root.player.canTogglePlaying
                            onClicked: root.player.togglePlaying()
                        }
                        IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: root.gNext; size: 30
                            active: root.hasMedia && root.player.canGoNext
                            onClicked: root.player.next()
                        }
                    }
                    Item { width: 1; height: 22 }
                    Wave {
                        anchors.horizontalCenter: parent.horizontalCenter
                        maxH: 28
                        barW: 5
                        opacity: root.playing ? 0.9 : 0.3
                    }
                }

                IconButton {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 28
                    glyph: String.fromCodePoint(0xF0156)
                    size: 18
                    onClicked: root.showPlayer = false
                }
                Text {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 26
                    text: (root.player ? root.player.identity + "   ·   " : "") + "Space play/pause   ←/→ seek   N/P next/previous   Esc close"
                    font.family: root.font
                    font.pixelSize: 12
                    color: root.fg3
                }
            }
        }
    }
}
