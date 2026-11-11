pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// Live video wallpaper through mpvpaper (a separate, maintained renderer:
// mpv decodes — with hardware decoding when the driver supports it — and
// draws onto the background layer itself).
//
// Lifecycle rules, all enforced here:
//   * runs only when a video is set, mpvpaper is installed, and the
//     PerformanceService allows it (not in safe mode; not on battery or
//     power-saver when "pause on battery" is on)
//   * stopped while the screen is locked and while a fullscreen window is
//     focused (mpvpaper -p also pauses when it's fully covered)
//   * the file must exist and be a video container we accept; anything else
//     is refused with a reason, and the static wallpaper stays
//   * crash loop protection: 3 failures → disabled until the video changes
// The static wallpaper is always drawn underneath, so a stopped or failed
// video never leaves an empty desktop.
Singleton {
    id: root

    property bool installed: false
    readonly property string video: Config.wallpaper.video || ""
    property bool locked: false                    // bound from the lock screen
    property bool fileOk: false
    property string reason: ""
    property int _failures: 0

    readonly property bool wanted: video.length > 0
    readonly property bool allowed: installed && fileOk && PerformanceService.videoAllowed && !locked
        && !WindowService.fullscreenActive && _failures < 3
    readonly property bool playing: mpv.running

    readonly property string state: !wanted ? "off"
        : !installed ? "mpvpaper is not installed (sudo dnf install mpvpaper)"
        : !fileOk ? (reason || "checking the file…")
        : _failures >= 3 ? "stopped after repeated failures"
        : locked ? "paused while locked"
        : WindowService.fullscreenActive ? "paused for a fullscreen window"
        : !PerformanceService.videoAllowed ? "paused to save power"
        : "playing"

    Process {
        id: probe
        command: ["sh", "-c", "command -v mpvpaper >/dev/null"]
        onExited: function(code) { root.installed = code === 0; }
    }

    // Validate: a regular, readable file with a video extension.
    Process {
        id: check
        command: ["sh", "-c", '[ -f "$1" ] && [ -r "$1" ]', "sh", root.video]
        onExited: function(code) {
            const extOk = /\.(mp4|webm|mkv|mov|m4v|avi|ogv)$/i.test(root.video);
            root.fileOk = code === 0 && extOk;
            root.reason = code !== 0 ? "the video file can't be read" : (!extOk ? "unsupported file type" : "");
        }
    }
    onVideoChanged: { root._failures = 0; root.fileOk = false; if (root.wanted) check.running = true; }

    // Started/stopped explicitly (not bound): the retry path must be able to
    // restart it without severing a binding that also has to stop it.
    onAllowedChanged: mpv.running = root.allowed
    Process {
        id: mpv
        // '*' = every output. no-audio: a wallpaper is never heard.
        // hwdec=auto-safe: hardware decoding only where mpv knows it's reliable.
        command: ["mpvpaper", "-p", "-o", "no-audio loop hwdec=auto-safe panscan=1.0 --really-quiet", "*", root.video]
        onExited: function(code) {
            if (root.allowed && code !== 0) {
                root._failures += 1;
                Logger.warn("VideoWallpaperService", "mpvpaper exited with " + code + " (" + root._failures + "/3)");
                if (root._failures < 3) retry.restart();
            }
        }
    }
    Timer { id: retry; interval: 2000; onTriggered: if (root.allowed && !mpv.running) mpv.running = true }

    Component.onCompleted: { probe.running = true; if (root.wanted) check.running = true; }
    Component.onDestruction: mpv.running = false
}
