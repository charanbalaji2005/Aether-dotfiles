pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Config engine: binds ~/.config/aether-shell/config.json directly to QML
// properties via Quickshell's FileView + JsonAdapter idiom. Editing the file
// on disk updates the running shell (the `aether theme` CLI relies on this);
// changing a bound property writes it back out. Defaults below double as the
// schema documentation — keys missing from an older config.json simply take
// these values, so upgrading never requires editing the file.
Singleton {
    id: root

    property bool ready: false

    property alias bar: adapter.bar
    property alias appearance: adapter.appearance
    property alias general: adapter.general
    property alias notifications: adapter.notifications
    property alias launcher: adapter.launcher
    property alias performance: adapter.performance
    property alias nightLight: adapter.nightLight

    // Best-effort directory bootstrap so the very first write doesn't fail
    // on a machine that has never run AetherOS Shell before.
    Process {
        id: ensureDir
        command: ["mkdir", "-p", Paths.configDir]
    }
    Component.onCompleted: ensureDir.running = true

    // First run (no config.json yet): `loaded` never fires, but the defaults
    // are already in place — mark ready so dependants don't wait forever.
    Timer {
        interval: 1500
        running: !root.ready
        onTriggered: root.ready = true
    }

    FileView {
        id: file
        path: Paths.configFile
        watchChanges: true
        printErrors: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoaded: root.ready = true

        adapter: JsonAdapter {
            id: adapter

            property JsonObject bar: JsonObject {
                property string position: "top"      // "top" | "bottom"
                property string style: "floating"    // "full" (edge to edge) | "floating" (inset island) | "dock" (centred, content-width)
                property int height: 38
                property var modules: ["workspaces", "activeWindow", "tray", "network", "audio", "battery", "clock"]
                property bool showLauncher: true
                property bool showActiveWindow: true
                property bool showStats: true        // CPU / RAM / GPU chips
                property bool showTemperatures: true // temperatures inside the stat chips
                property bool showNetSpeed: false
                property bool showNetwork: true
                property bool showAudio: true
                property bool showMicrophone: true
                property bool showBattery: true
                property bool showMedia: true
                property bool showBluetooth: true
                property bool showNotifications: true
                property bool showTray: true
            }

            property JsonObject appearance: JsonObject {
                property string theme: "dark"         // "dark" | "light" | "auto" (light between autoLightFrom and autoDarkFrom)
                property int autoLightFrom: 7         // hour, 0-23
                property int autoDarkFrom: 19
                property bool syncGtk: true           // also set GTK/libadwaita color-scheme via gsettings
                property string accent: "#7C9CFF"
                property string accentMode: "manual"  // "manual" | "wallpaper" (derive from wallpaper, needs ImageMagick)
                property real barOpacity: 0.72
                property real panelOpacity: 0.80      // glass opacity of popups/panels
                property string compositorBlur: "profile" // "profile" (leave to Hyprland profile) | "on" | "off"
                property string wallpaper: ""
                property var wallpapers: ({})         // per-output overrides: { "DP-1": "/path.jpg" }
                property bool enableBackground: true
                property real wallpaperDim: 0.0
                property real wallpaperBlur: 0.0      // 0 = off, 1 = strongest; rendered once, not per frame
                property bool animatedWallpapers: false // play GIFs; paused automatically on battery
            }

            property JsonObject general: JsonObject {
                property bool reducedMotion: false
                property real animationSpeed: 1.0     // 0.5 - 2.0
                property bool use24Hour: true
            }

            property JsonObject notifications: JsonObject {
                property bool doNotDisturb: false
                property int timeoutLow: 4000         // ms
                property int timeoutNormal: 6000      // ms; critical notifications never time out
                property int maxVisible: 4            // toasts on screen at once
                property bool groupByApp: true
            }

            property JsonObject launcher: JsonObject {
                property var favorites: []            // desktop file ids, e.g. "firefox.desktop"
                property var recents: []              // most recent first
                property int recentLimit: 8
                property bool showCategories: true
            }

            property JsonObject performance: JsonObject {
                property int telemetryInterval: 2000  // ms between system samples (bar + dashboard)
                property bool pauseOnBattery: false   // halve sampling on battery power
            }

            property JsonObject nightLight: JsonObject {
                property int temperature: 4500        // Kelvin, used by hyprsunset
            }
        }
    }
}
