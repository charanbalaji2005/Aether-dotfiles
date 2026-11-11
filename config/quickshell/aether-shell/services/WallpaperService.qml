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
    // image path without extension -> depth map path (<name>.depth.png next to it)
    property var depthMaps: ({})
    // Transition chosen for the change in progress (resolves "random").
    property string activeTransition: "fade"
    readonly property var transitions: ["fade", "zoom", "slide", "wipe", "circle", "dissolve", "blinds"]

    function depthFor(path) {
        if (!path) return "";
        const base = path.replace(/\.[^./]+$/, "");
        return root.depthMaps[base] || "";
    }

    function _pickTransition() {
        const t = Config.wallpaper.transition || "fade";
        if (t !== "random") return t;
        const opts = root.transitions.filter(function(x) { return x !== root.activeTransition; });
        return opts[Math.floor(Math.random() * opts.length)];
    }

    // ── Favourites ────────────────────────────────────────────────────
    function isFavorite(path) { return (Config.wallpaper.favorites || []).indexOf(path) >= 0; }
    function toggleFavorite(path) {
        const f = (Config.wallpaper.favorites || []).slice();
        const i = f.indexOf(path);
        if (i >= 0) f.splice(i, 1); else f.push(path);
        Config.wallpaper.favorites = f;
    }

    // ── Scheduling ────────────────────────────────────────────────────
    // "interval": next wallpaper (favourites if any, else all) every N
    // minutes. "daynight": day/night wallpapers at the theme's auto hours.
    // One timer, only while a schedule is on.
    readonly property string schedule: Config.wallpaper.schedule || "off"
    Timer {
        running: root.schedule === "interval" && root.available
        interval: Math.max(1, Config.wallpaper.intervalMinutes) * 60000
        repeat: true
        onTriggered: {
            const favs = (Config.wallpaper.favorites || []).filter(function(f) { return root.wallpapers.some(function(w) { return w.path === f; }); });
            if (favs.length > 1) {
                const i = favs.indexOf(root.currentWallpaper);
                root.setWallpaper(favs[(i + 1) % favs.length]);
            } else root.nextWallpaper();
        }
    }
    Timer {
        running: root.schedule === "daynight"
        interval: 60000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const h = new Date().getHours();
            const day = h >= Config.appearance.autoLightFrom && h < Config.appearance.autoDarkFrom;
            const want = day ? Config.wallpaper.dayWallpaper : Config.wallpaper.nightWallpaper;
            if (want && want.length > 0 && want !== root.currentWallpaper) root.setWallpaper(want);
        }
    }

    readonly property string _scanScript: [
        'for d in "$HOME/.config/aether-shell/wallpapers" "$HOME/.local/share/wallpapers/aetheros" "$HOME/.local/share/wallpapers" "$HOME/Pictures/Wallpapers" /usr/share/wallpapers /usr/share/backgrounds; do',
        '  [ -d "$d" ] || continue',
        '  find "$d" -maxdepth 2 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.jxl" -o -iname "*.gif" \\) 2>/dev/null',
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

        const depth = {};
        for (const path of lines) {
            const m = path.match(/^(.*)\.depth\.(png|jpe?g|webp)$/i);
            if (m) depth[m[1]] = path;
        }
        root.depthMaps = depth;
        for (const path of lines) {
            const filename = path.split("/").pop();
            if (/\.depth\.(png|jpe?g|webp)$/i.test(filename)) continue;
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
        if (path !== root.currentWallpaper) root.activeTransition = root._pickTransition();
        root.currentWallpaper = path;
        const filename = path.split("/").pop();
        root.currentTitle = root._humanizeTitle(filename);

        if (Config.ready && Config.appearance) {
            Config.appearance.wallpaper = path;
        }

        // Write state file and notify daemons
        // The path is passed as a positional argument ($1), never spliced
        // into the script text: a file named e.g. `$(rm -rf ~).jpg` must be
        // treated as data. (The previous version interpolated it — fixed.)
        applyProcess.command = [
            "sh", "-c",
            'mkdir -p "$HOME/.config/aether-shell" && printf "%s\\n" "$1" > "$HOME/.config/aether-shell/current_wallpaper"',
            "sh", path
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

    // ── Per-display wallpapers ─────────────────────────────────────────
    // Config.appearance.wallpapers maps output name -> path. Outputs without
    // an entry show the global wallpaper.
    function wallpaperFor(screenName) {
        const map = Config.appearance.wallpapers || {};
        const p = map[screenName];
        return (p && p.length > 0) ? p : root.currentWallpaper;
    }

    function setWallpaperFor(screenName, path) {
        if (!screenName || !path) return;
        const map = Object.assign({}, Config.appearance.wallpapers || {});
        map[screenName] = path;
        Config.appearance.wallpapers = map;
        EventBus.notificationRequested("Wallpaper Applied", root._humanizeTitle(path.split("/").pop()) + " on " + screenName, "low");
    }

    function clearWallpaperFor(screenName) {
        const map = Object.assign({}, Config.appearance.wallpapers || {});
        delete map[screenName];
        Config.appearance.wallpapers = map;
    }

    function isAnimated(path) {
        return /\.gif$/i.test(path || "");
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

    // If the scan finished before config.json was loaded, the first wallpaper
    // was picked as a placeholder; switch to the saved choice once Config is ready.
    Connections {
        target: Config
        function onReadyChanged() {
            const saved = Config.appearance ? Config.appearance.wallpaper : "";
            if (Config.ready && saved && saved.length > 0 && saved !== root.currentWallpaper) root._setCurrent(saved, false);
        }
    }

    Component.onCompleted: refresh()
}
