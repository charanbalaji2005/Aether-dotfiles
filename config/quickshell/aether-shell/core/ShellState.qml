pragma Singleton
import Quickshell

// Session-wide UI state shared across layers. Like Colors.accent, these are
// bound once at the shell root (shell.qml) from services, so components can
// read them without importing system services themselves.
Singleton {
    // The QScreen of the Hyprland-focused monitor; popups open there.
    property var activeScreen: null
    // True while running on battery (used to pause animated wallpapers).
    property bool onBattery: false
}
