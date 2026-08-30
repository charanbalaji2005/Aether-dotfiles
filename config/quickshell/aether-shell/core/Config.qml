pragma Singleton
import Quickshell
import Quickshell.Io

// Config engine: binds ~/.config/aether-shell/config.json directly to QML
// properties via Quickshell's FileView + JsonAdapter idiom. Editing the file
// on disk updates the running shell; changing a bound property writes it
// back out. Defaults below double as the schema documentation.
Singleton {
    id: root

    property bool ready: false

    property alias bar: adapter.bar
    property alias appearance: adapter.appearance
    property alias general: adapter.general

    // Best-effort directory bootstrap so the very first write doesn't fail
    // on a machine that has never run AetherOS Shell before.
    Process {
        id: ensureDir
        command: ["mkdir", "-p", Paths.configDir]
    }
    Component.onCompleted: ensureDir.running = true

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
                property string position: "top" // "top" | "bottom"
                property int height: 38
                property var modules: ["workspaces", "activeWindow", "tray", "network", "audio", "battery", "clock"]
                property bool showNetwork: true
                property bool showAudio: true
                property bool showBattery: true
                property bool showMedia: true
                property bool showBluetooth: true
            }

            property JsonObject appearance: JsonObject {
                property string accent: "#7C9CFF"
                property real barOpacity: 0.72
                property string wallpaper: ""
                property bool enableBackground: true
                property real wallpaperDim: 0.0
            }

            property JsonObject general: JsonObject {
                property bool reducedMotion: false
            }
        }
    }
}
