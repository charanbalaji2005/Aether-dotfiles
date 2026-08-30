pragma Singleton
import Quickshell

Singleton {
    readonly property string home: Quickshell.env("HOME") || "/tmp"
    readonly property string configDir: home + "/.config/aether-shell"
    readonly property string configFile: configDir + "/config.json"
}
