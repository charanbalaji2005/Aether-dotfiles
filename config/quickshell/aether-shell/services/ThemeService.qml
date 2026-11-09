pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// Resolves the theme the shell should use and keeps the rest of the desktop
// in step with it:
//   * dark / light / auto (light between Config.appearance.autoLightFrom and
//     autoDarkFrom), re-evaluated once a minute — not per frame
//   * GTK/libadwaita colour scheme via gsettings (optional)
//   * accent colour derived from the wallpaper (`aether theme accent`,
//     ImageMagick) when accentMode is "wallpaper"
//   * compositor blur override via `hyprctl keyword`, re-applied after
//     Hyprland reloads its config
Singleton {
    id: root

    property bool isDark: true
    readonly property string mode: Config.appearance.theme || "dark"
    property string accentError: ""
    property bool extracting: false

    function _resolve() {
        if (root.mode === "light") return false;
        if (root.mode === "dark") return true;
        const h = new Date().getHours();
        const from = Config.appearance.autoLightFrom, to = Config.appearance.autoDarkFrom;
        return !(h >= from && h < to);
    }

    function evaluate() {
        const dark = root._resolve();
        if (dark !== root.isDark) {
            root.isDark = dark;
            EventBus.themeChanged();
        }
        root._syncGtk();
    }

    Timer {
        interval: 60000
        running: root.mode === "auto"
        repeat: true
        onTriggered: root.evaluate()
    }

    onModeChanged: evaluate()

    // ── GTK colour scheme ──────────────────────────────────────────────
    property string _gtkApplied: ""
    Process { id: gsettings }

    function _syncGtk() {
        if (!Config.appearance.syncGtk) return;
        const scheme = root.isDark ? "prefer-dark" : "prefer-light";
        if (scheme === root._gtkApplied) return;
        root._gtkApplied = scheme;
        gsettings.command = ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", scheme];
        gsettings.running = true;
    }

    // ── Wallpaper accent ───────────────────────────────────────────────
    Process {
        id: accentProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const c = this.text.trim();
                if (/^#[0-9A-Fa-f]{6}$/.test(c)) {
                    Config.appearance.accent = c;
                    root.accentError = "";
                    Logger.info("ThemeService", "Wallpaper accent " + c);
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: { const e = this.text.trim(); if (e.length > 0) root.accentError = e; }
        }
        onExited: root.extracting = false
    }

    function accentFromWallpaper(path) {
        if (!path || accentProcess.running) return;
        root.extracting = true;
        accentProcess.command = Paths.aether(["theme", "accent", path, "--mode", root.isDark ? "dark" : "light"]);
        accentProcess.running = true;
    }

    // ── Compositor blur ────────────────────────────────────────────────
    Process { id: hyprBlur }

    readonly property string blurPreference: Config.appearance.compositorBlur || "profile"
    property string _blurApplied: "profile"

    function applyCompositorBlur() {
        if (!HyprlandService.available) return;
        const pref = root.blurPreference;
        if (pref === "on" || pref === "off") {
            hyprBlur.command = ["hyprctl", "keyword", "decoration:blur:enabled", pref === "on" ? "true" : "false"];
            hyprBlur.running = true;
        } else if (root._blurApplied !== "profile") {
            // Back to "follow the profile": reload restores the configured value
            // (a config reload, not a compositor restart).
            hyprBlur.command = ["hyprctl", "reload"];
            hyprBlur.running = true;
        }
        root._blurApplied = pref;
    }

    onBlurPreferenceChanged: if (Config.ready) applyCompositorBlur()

    Connections {
        target: HyprlandService
        // `hyprctl reload` resets runtime keywords; re-apply our override.
        function onConfigReloaded() {
            if (root.blurPreference === "on" || root.blurPreference === "off") root.applyCompositorBlur();
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return;
            root.evaluate();
            root.applyCompositorBlur();
        }
    }

    // Wallpaper-derived accent.
    readonly property string wallpaperPath: WallpaperService.currentWallpaper
    readonly property string accentModeSetting: Config.appearance.accentMode || "manual"
    onWallpaperPathChanged: if (root.accentModeSetting === "wallpaper") root.accentFromWallpaper(root.wallpaperPath)
    onAccentModeSettingChanged: if (root.accentModeSetting === "wallpaper") root.accentFromWallpaper(root.wallpaperPath)
    onIsDarkChanged: if (root.accentModeSetting === "wallpaper") root.accentFromWallpaper(root.wallpaperPath)

    Component.onCompleted: evaluate()
}
