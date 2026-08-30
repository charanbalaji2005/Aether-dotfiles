pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// Manages desktop wallpapers: discovers images from standard XDG and AetherOS
// paths, provides random and sequential selection, tracks the current wallpaper,
// and synchronizes with Config.appearance.wallpaper and external tools.
Singleton {
    id: root

    property bool available: false
    property string currentWallpaper: ""
    property string currentTitle: ""
    property var wallpapers: [] // [{ path, filename, title, uri }]
    property real dimOverlay: Config.ready && Config.appearance ? (Config.appearance.wallpaperDim || 0.0) : 0.0

    readonly property string _scanScript: [
        'for d in "$HOME/.config/aether-shell/wallpapers" "$HOME/.local/share/wallpapers/aetheros" "$HOME/.local/share/wallpapers" "$HOME/Pictures/Wallpapers" /usr/share/wallpapers /usr/share/backgrounds; do',
        '  [ -d "$d" ] || continue',
        '  find "$d" -maxdepth 2 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.jxl" \\) 2>/dev/null',
        'done'
    ].join("\n")

    Process {
        id: scanProcess
        command: ["bash", "-c", root._scanScript]
        stdout: StdioCollector {
            onStreamFinished: root._parse(this.text)
        }
    }

    Process {
        id: applyProcess
    }

    function refresh() {
        scanProcess.running = true;
    }

    function _humanizeTitle(filename) {
        // Remove extension
        let name = filename.replace(/\.[a-zA-Z0-9]+$/, "");
        // Remove resolution tags like -5120x2880-25362, -7680x4320, -4k, -8k, etc.
        name = name.replace(/[-_]\d+x\d+([-_]\d+)?/gi, "");
        name = name.replace(/[-_][48]k(-wallpapers)?/gi, "");
        // Replace dashes and underscores with spaces
        name = name.replace(/[-_]+/g, " ").trim();
        // Capitalize words
        return name.replace(/\b\w/g, function(l) { return l.toUpperCase(); });
    }

    function _parse(text) {
        const lines = text.split("\n").map(function(l) { return l.trim(); }).filter(function(l) { return l.length > 0; });
        const seen = {};
        const result = [];

        for (const path of lines) {
            const filename = path.split("/").pop();
            if (seen[filename]) continue;
            seen[filename] = true;

            const title = root._humanizeTitle(filename);
            result.push({
                path: path,
                filename: filename,
                title: title,
                uri: "file://" + path
            });
        }

        result.sort(function(a, b) { return a.title.localeCompare(b.title); });
        root.wallpapers = result;
        root.available = result.length > 0;
        Logger.info("WallpaperService", "Discovered " + result.length + " wallpapers");

        // Initialize current wallpaper
        if (!root.currentWallpaper || root.currentWallpaper.length === 0) {
            if (Config.ready && Config.appearance && Config.appearance.wallpaper && Config.appearance.wallpaper.length > 0) {
                root._setCurrent(Config.appearance.wallpaper, false);
            } else if (result.length > 0) {
                root._setCurrent(result[0].path, false);
            }
        }
    }

    function _setCurrent(path, notify) {
        root.currentWallpaper = path;
        const filename = path.split("/").pop();
        root.currentTitle = root._humanizeTitle(filename);

        if (Config.ready && Config.appearance) {
            Config.appearance.wallpaper = path;
        }

        // Write state file and notify daemons
        applyProcess.command = [
            "bash", "-c",
            'mkdir -p "$HOME/.config/aether-shell" && echo "' + path + '" > "$HOME/.config/aether-shell/current_wallpaper"'
        ];
        applyProcess.running = true;

        if (notify) {
            Logger.info("WallpaperService", "Wallpaper set to: " + root.currentTitle);
            EventBus.notificationRequested("Wallpaper Applied", root.currentTitle, "normal");
        }
    }

    function setWallpaper(path) {
        if (!path || path.length === 0) return;
        root._setCurrent(path, true);
    }

    function randomWallpaper() {
        if (root.wallpapers.length === 0) return;
        if (root.wallpapers.length === 1) {
            root.setWallpaper(root.wallpapers[0].path);
            return;
        }

        const candidates = root.wallpapers.filter(function(w) { return w.path !== root.currentWallpaper; });
        const list = candidates.length > 0 ? candidates : root.wallpapers;
        const idx = Math.floor(Math.random() * list.length);
        root.setWallpaper(list[idx].path);
    }

    function nextWallpaper() {
        if (root.wallpapers.length === 0) return;
        let idx = 0;
        for (let i = 0; i < root.wallpapers.length; i++) {
            if (root.wallpapers[i].path === root.currentWallpaper) {
                idx = (i + 1) % root.wallpapers.length;
                break;
            }
        }
        root.setWallpaper(root.wallpapers[idx].path);
    }

    function prevWallpaper() {
        if (root.wallpapers.length === 0) return;
        let idx = 0;
        for (let i = 0; i < root.wallpapers.length; i++) {
            if (root.wallpapers[i].path === root.currentWallpaper) {
                idx = (i - 1 + root.wallpapers.length) % root.wallpapers.length;
                break;
            }
        }
        root.setWallpaper(root.wallpapers[idx].path);
    }

    function search(query) {
        if (!query || query.trim().length === 0) {
            return root.wallpapers;
        }
        const q = query.toLowerCase();
        return root.wallpapers.filter(function(w) {
            return w.title.toLowerCase().indexOf(q) >= 0 || w.filename.toLowerCase().indexOf(q) >= 0;
        });
    }

    Component.onCompleted: refresh()
}
