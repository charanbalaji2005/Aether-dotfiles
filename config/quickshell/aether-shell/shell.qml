import QtQuick
import QtQml
import Quickshell
import "./theme"
import "./core"
import "./shell/bar"
import "./shell/launcher"
import "./shell/notifications"
import "./shell/clipboard"
import "./shell/screenshot"
import "./shell/lockscreen"
import "./shell/powermenu"
import "./shell/dashboard"
import "./shell/settings"
import "./shell/bluetooth"
import "./shell/wallpaper"

ShellRoot {
    // Keeps the theme's accent token in sync with the user's Settings
    // choice, persisted via Config. Colors.qml itself stays config-agnostic
    // (see the comment on Colors.accent) — this is the one place that
    // bridges theme and config, deliberately kept at the shell root.
    Binding {
        target: Colors
        property: "accent"
        value: Config.appearance.accent
    }

    Binding {
        target: Motion
        property: "reducedMotion"
        value: Config.general.reducedMotion
    }

    WallpaperBackground {}
    Bar {}
    Launcher {}
    NotificationPopup {}
    NotificationCenter {}
    ClipboardHistory {}
    ScreenshotController {}
    WallpaperPicker {}
    LockScreen {}
    PowerMenu {}
    Dashboard {}
    Settings {}
    BluetoothManager {}
}
