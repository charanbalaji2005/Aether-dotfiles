pragma Singleton
import Quickshell

// Lightweight pub/sub hub so unrelated modules don't need direct references
// to each other. Most UI binds directly to service properties (simpler and
// fully reactive); this exists for cross-cutting actions.
Singleton {
    signal workspaceChanged(int id)
    signal activeWindowChanged(string title, string appId)
    signal audioChanged(real volume, bool muted)
    signal batteryChanged(real percentage, string state)
    signal networkChanged(bool connected, string kind, int signalStrength)
    signal trayItemsChanged()
    signal themeChanged()
    signal configReloaded()
    // Shell-originated notifications (screenshot saved, wallpaper applied…).
    // NotificationService turns these into real toasts + history entries.
    signal notificationRequested(string title, string body, string urgency)
    signal lockRequested()
    signal bluetoothManagerRequested()
    // Panels that other panels can open.
    signal controlCenterRequested()
    signal dashboardRequested()
    signal notificationCenterRequested()
    signal launcherRequested()
    signal settingsRequested(string section)
    signal wallpaperPickerRequested()
    signal powerMenuRequested()
    // On-screen display for volume/brightness changes.
    signal osdRequested(string kind, real value, bool muted)
    // Ask every popup to close (used before opening another one).
    signal closePopups(string except)
}
