import QtQuick
import QtQml
import Quickshell
import "./theme"
import "./core"
import "./services"
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
import "./shell/controlcenter"
import "./shell/osd"

ShellRoot {
    // ── Theme ↔ config/service bridges ─────────────────────────────────
    // theme/ and core/ stay free of service imports; this is the one place
    // that connects them (see ARCHITECTURE.md).
    Binding { target: Colors; property: "accent"; value: Config.appearance.accent }
    Binding { target: Colors; property: "dark"; value: ThemeService.isDark }
    Binding { target: Colors; property: "glassOpacity"; value: Config.appearance.panelOpacity }
    Binding { target: Motion; property: "reducedMotion"; value: Config.general.reducedMotion }
    Binding { target: Motion; property: "speed"; value: Config.general.animationSpeed }
    Binding { target: ShellState; property: "activeScreen"; value: HyprlandService.focusedScreen }
    Binding { target: ShellState; property: "onBattery"; value: PowerService.available && !PowerService.charging && !PowerService.fullyCharged }

    WallpaperBackground {}
    Bar {}
    Launcher {}
    ControlCenter {}
    Dashboard {}
    NotificationPopup {}
    NotificationCenter {}
    ClipboardHistory {}
    ScreenshotController {}
    WallpaperPicker {}
    LockScreen {}
    PowerMenu {}
    Settings {}
    BluetoothManager {}
    OSD {}
}
