pragma Singleton
import Quickshell

Singleton {
    readonly property string home: Quickshell.env("HOME") || "/tmp"
    readonly property string configDir: home + "/.config/aether-shell"
    readonly property string configFile: configDir + "/config.json"
    readonly property string stateFile: configDir + "/current_wallpaper"

    // Run an AetherOS helper (aether, aether-screenshot, ...) by name.
    // ~/.local/bin is prepended because systemd user units and some display
    // managers start the session without it on PATH. Arguments are passed
    // positionally — never interpolated into the shell string — so no value
    // can be interpreted as shell syntax.
    function helper(name, args) {
        return ["sh", "-c", 'PATH="$HOME/.local/bin:$PATH"; exec "$0" "$@"', name].concat(args || []);
    }

    function aether(args) {
        return helper("aether", args);
    }
}
