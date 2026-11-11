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
    property alias meta: adapter.meta
    property alias effects: adapter.effects
    property alias wallpaper: adapter.wallpaper
    property alias dock: adapter.dock
    property alias island: adapter.island
    property alias battery: adapter.battery
    property alias lock: adapter.lock
    property alias gestures: adapter.gestures
    property alias automation: adapter.automation
    property alias overview: adapter.overview
    property alias accessibility: adapter.accessibility
    property alias terminal: adapter.terminal
    property alias input: adapter.input
    property alias workspaces: adapter.workspaces
    property alias ai: adapter.ai
    property alias widgets: adapter.widgets
    property alias power: adapter.power
    property alias privacy: adapter.privacy

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
                property string palette: "aether"     // id from theme/Palettes.js
                property string glassStyle: "medium"  // "opaque" | "light" | "medium" | "heavy" | "ultra" | "adaptive" | "custom" (custom = panelOpacity)
                property bool accentBorders: true     // accent-tinted hairline on focused surfaces
                property real cornerScale: 1.0        // 0.0 (square) - 1.5, multiplies every radius token
            }

            property JsonObject general: JsonObject {
                property bool reducedMotion: false
                property string motionProfile: "smooth" // "none" | "reduced" | "balanced" | "smooth" | "premium"
                property bool xdgAutostart: true      // run ~/.config/autostart and /etc/xdg/autostart entries at login
                property real animationSpeed: 1.0     // 0.5 - 2.0
                property bool use24Hour: true
            }

            property JsonObject notifications: JsonObject {
                property bool doNotDisturb: false
                property int timeoutLow: 4000         // ms
                property int timeoutNormal: 6000      // ms; critical notifications never time out
                property int maxVisible: 4            // toasts on screen at once
                property bool groupByApp: true
                property var appRules: []             // [{app, mode: "normal"|"priority"|"mute", sound}] (validated)
                property bool showOnLock: false       // toasts while locked (contents follow lock.hideNotificationContent)
            }

            property JsonObject launcher: JsonObject {
                property var favorites: []            // desktop file ids, e.g. "firefox.desktop"
                property var recents: []              // most recent first
                property int recentLimit: 8
                property bool showCategories: true
                property bool searchFiles: true       // "/query" searches your files (plocate if installed, else a bounded scan)
                property bool searchSettings: true
                property bool commandMode: true       // ">command" runs in your terminal after Enter (never on its own)
                property var history: []              // recent queries (cleared from Settings → Privacy)
                property int historyLimit: 20
            }

            property JsonObject performance: JsonObject {
                property int telemetryInterval: 2000  // ms between system samples (bar + dashboard)
                property bool pauseOnBattery: false   // halve sampling on battery power
            }

            // Schema version of this file; `aether config migrate` upgrades older files.
            property JsonObject meta: JsonObject {
                property int schemaVersion: 4
            }

            // Graphics quality. "auto" follows hardware, power state and frame pacing
            // (see services/PerformanceService.qml for every rule and its reason).
            property JsonObject effects: JsonObject {
                property string quality: "auto"       // "auto" | "eco" | "performance" | "balanced" | "ultra"
                property bool gpuPressure: true       // step effects down when the GPU or its memory is under pressure
                property real vramThreshold: 0.88     // fraction of VRAM in use that counts as pressure
                property real gpuThreshold: 0.92      // GPU utilisation that counts as pressure
                property bool shaders: true           // allow ShaderEffect materials at all
                property bool adaptive: true          // step down when frames run late
                property bool particles: true         // ambient particle layers (ultra only)
                property bool glow: true              // animated accent edge on focused surfaces
                property bool springs: true           // physics springs (off = plain easing)
            }

            property JsonObject wallpaper: JsonObject {
                property string transition: "fade"    // "none" | "fade" | "zoom" | "slide" | "wipe" | "circle" | "dissolve" | "blinds" | "random"
                property int transitionDuration: 900  // ms
                property bool parallax: false         // pointer-driven depth (needs a <name>.depth.png or uses a flat shift)
                property real parallaxStrength: 0.35  // 0-1
                property string ambient: "none"       // "none" | "stars" | "snow" | "rain" | "dust" | "aurora"
                property real ambientDensity: 0.5     // 0-1
                property string schedule: "off"       // "off" | "interval" | "daynight"
                property int intervalMinutes: 30
                property string dayWallpaper: ""
                property string nightWallpaper: ""
                property string video: ""             // path to a video; played by mpvpaper when installed
                property string mode: "image"         // "image" | "gradient" | "aurora"
                property var perWorkspace: ({})       // workspace id -> image path
                property bool videoPauseOnBattery: true
                property var favorites: []
            }

            property JsonObject dock: JsonObject {
                property bool enabled: false
                property string position: "bottom"    // "bottom" | "left" | "right"
                property int iconSize: 44
                property real magnification: 1.45     // 1.0 = off
                property bool autoHide: true
                property bool showRunning: true       // running apps that are not favourites
                property bool showTrash: false
                property bool showRecent: true        // recently launched apps that aren't pinned or running
                property bool previews: true          // window thumbnails in the right-click menu (needs screencopy)
                property real opacity: 0.72
            }

            property JsonObject island: JsonObject {
                property bool enabled: true
                property bool showMedia: true
                property bool showTimers: true
                property bool showBattery: true
                property bool showRecording: true
                property bool showNotifications: true
                property bool visualizer: true        // spectrum bars while music plays (needs cava)
                property bool showPrivacy: true       // microphone / camera in use (PipeWire streams)
                property bool showNetwork: true       // connected / disconnected / VPN
                property bool showClipboard: false    // "copied" (never the content)
                property bool showScreenshots: true
                property bool allowExternal: true     // `aether island post` / IPC from your own scripts
                property int eventSeconds: 4
            }

            property JsonObject battery: JsonObject {
                property string style: "classic"      // "classic" | "outline" | "filled" | "segmented" | "circular" | "percent" | "compact" | "bar"
                property bool showPercentage: true
                property int lowThreshold: 20
                property int criticalThreshold: 10
                property bool notifyLow: true
                property bool notifyFull: false
                property string colorCharging: ""     // "" = theme colour
                property string colorNormal: ""
                property string colorLow: ""
                property string colorCritical: ""
            }

            property JsonObject lock: JsonObject {
                property string clockStyle: "digital" // "digital" | "large" | "split" | "analog"
                property string backend: "aether"     // "aether" | "hyprlock" (used only when hyprlock is installed)
                property bool showDate: true
                property bool showBattery: true
                property bool showMedia: true
                property bool blurBackground: true
                property int idleLockMinutes: 10      // 0 = never; written to hypridle.conf by `aether idle apply`
                property int idleDisplayOffMinutes: 15
                property int idleSuspendMinutes: 0
                property bool hideNotificationContent: true
            }

            property JsonObject gestures: JsonObject {
                property bool edgesEnabled: false
                property string edgeLeft: "launcher"  // action ids, see services/ActionService.qml
                property string edgeRight: "controlcenter"
                property string edgeTop: "none"
                property string edgeBottom: "none"
                property int edgeDwellMs: 220
                property string swipeUp: "overview"   // 3-finger touchpad swipes, written by `aether hyprland compat`
                property string swipeDown: "none"
                property bool workspaceSwipe: true
            }

            property JsonObject automation: JsonObject {
                property bool enabled: false
                property var rules: []                // validated by automation/Rules.js and `aether automation validate`
            }

            property JsonObject overview: JsonObject {
                property bool thumbnails: true        // live window previews when the compositor allows it
                property bool showEmpty: true         // show one empty workspace to drag windows into
            }

            property JsonObject accessibility: JsonObject {
                property real uiScale: 1.0            // 0.85 - 1.5, multiplies type and spacing tokens
                property bool highContrast: false
                property bool colorBlind: false       // Okabe-Ito status colours
                property bool focusRings: true
            }

            // Terminal + shell (written by `aether theme apply`; kitty reloads live).
            property JsonObject terminal: JsonObject {
                property string preferred: "auto"     // "auto" | "kitty" | "ghostty" | "wezterm" | "alacritty" | "foot" | "ptyxis" | "gnome-terminal"
                property real opacity: 0.88           // kitty background_opacity
                property real fontSize: 11.0
                property string fontFamily: "JetBrains Mono"
                property int padding: 12
                property string cursorShape: "beam"   // "beam" | "block" | "underline"
                property string zshProfile: "developer" // "minimal" | "developer" | "power" | "custom"
                property string customProfile: ""     // path to your own zsh file, sourced by the "custom" profile
            }

            // Keyboard, mouse and touchpad (`aether input apply` → input.conf + live hyprctl).
            property JsonObject input: JsonObject {
                property string kbLayout: "us"        // comma-separated XKB layouts, validated against evdev.lst
                property string kbVariant: ""
                property string kbOptions: ""
                property int repeatRate: 35
                property int repeatDelay: 300
                property real sensitivity: 0.0        // -1 .. 1
                property string accelProfile: "adaptive" // "adaptive" | "flat"
                property bool naturalScroll: false
                property bool touchpadNaturalScroll: true
                property bool tapToClick: true
                property bool disableWhileTyping: true
                property real scrollFactor: 1.0
            }

            property JsonObject workspaces: JsonObject {
                property var names: ({})              // id -> name
                property var icons: ({})              // id -> AetherIcon name
                property var appRules: []             // [{app, workspace, silent}] → apprules.conf
                property bool restoreSession: false   // reopen saved apps at login
            }

            // AI assistant. Credentials are NEVER stored here: they live in
            // the Secret Service keyring (`aether ai set-key`).
            property JsonObject ai: JsonObject {
                property bool enabled: false
                property string provider: "ollama"    // "ollama" | "openai"
                property string endpoint: "http://127.0.0.1:11434"
                property string model: "llama3.2"
                property bool localOnly: true         // refuse non-loopback endpoints
                property bool shareSystemInfo: false  // include a hardware/telemetry summary as context
                property bool keepHistory: false
            }

            property JsonObject widgets: JsonObject {
                property bool enabled: false
                property var placed: []               // [{id, widget, screen, x, y, w, h}] validated by `aether widget`
                property bool allowThirdParty: false  // third-party widgets run inside the shell: off unless you opt in
                property var trusted: []              // [{id, digest}] — `aether widget trust`; a changed widget is untrusted again
                property int grid: 16
            }

            property JsonObject power: JsonObject {
                property bool autoSaver: false        // switch to power-saver at the threshold (opt-in)
                property int autoSaverThreshold: 20
                property int dimAfterMinutes: 0       // 0 = off; dims via brightnessctl before the display turns off
            }

            property JsonObject privacy: JsonObject {
                property int clipboardRetentionHours: 0  // 0 = keep (cliphist default); otherwise expire entries
                property var clipboardExcludeApps: []    // window classes whose copies aren't stored
                property bool notificationSounds: true
            }

            property JsonObject nightLight: JsonObject {
                property int temperature: 4500        // Kelvin, used by hyprsunset
            }
        }
    }
}
