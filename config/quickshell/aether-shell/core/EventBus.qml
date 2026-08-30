pragma Singleton
import Quickshell

// Lightweight pub/sub hub so unrelated modules don't need direct references
// to each other. Most Phase 1 UI binds directly to service properties
// (simpler and fully reactive on its own); this exists for the cases where
// something needs to react to a change without owning a binding to it, and
// for future cross-cutting features (notifications, theme switching).
Singleton {
    signal workspaceChanged(int id)
    signal activeWindowChanged(string title, string appId)
    signal audioChanged(real volume, bool muted)
    signal batteryChanged(real percentage, string state)
    signal networkChanged(bool connected, string kind, int signalStrength)
    signal trayItemsChanged()
    signal themeChanged()
    signal configReloaded()
    signal notificationRequested(string title, string body, string urgency)
    signal lockRequested()
    signal bluetoothManagerRequested()
}
