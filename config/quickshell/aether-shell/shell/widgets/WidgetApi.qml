import QtQuick
import "../../theme"
import "../../core"
import "../../services"

// The data a widget may see, filtered by the permissions in its manifest.
// One instance per widget. Anything not granted is simply absent (undefined),
// so a widget can't read what it didn't declare — and declarations are shown
// to the user before installation (`aether widget install`).
QtObject {
    id: api

    property var permissions: []
    function has(p) { return api.permissions.indexOf(p) >= 0; }

    readonly property int version: 1
    readonly property bool use24Hour: Config.general.use24Hour

    property date _now: new Date()
    readonly property var time: has("time") ? _now : undefined
    property Timer _clock: Timer {
        interval: 1000; repeat: true
        running: api.has("time")
        onTriggered: api._now = new Date()
    }

    readonly property var system: has("system") ? {
        cpu: SystemMonitorService.cpuUsage, mem: SystemMonitorService.memUsage, disk: SystemMonitorService.diskUsage,
        cpuTemp: SystemMonitorService.cpuTemp, uptime: SystemMonitorService.uptimeSeconds
    } : undefined

    readonly property var gpu: {
        if (!has("gpu")) return undefined;
        const g = SystemMonitorService.primaryGpu;
        if (!g) return { available: false, note: "No GPU telemetry" };
        // -1 means "not available" — never 0, which would read as a real value.
        const num = function(v) { return v === null || v === undefined ? -1 : v; };
        return { available: g.usage !== null && g.usage !== undefined, name: g.name, usage: num(g.usage),
                 vramUsed: num(g.vramUsed), vramTotal: num(g.vramTotal), tempC: num(g.tempC), note: g.note || "" };
    }

    readonly property var media: has("media") ? {
        available: MediaService.available, title: MediaService.title, artist: MediaService.artist,
        playing: MediaService.playing, artUrl: MediaService.artUrl,
        playPause: function() { MediaService.playPause(); }, next: function() { MediaService.next(); },
        previous: function() { MediaService.previous(); }
    } : undefined

    readonly property var battery: has("battery") ? {
        available: PowerService.available, level: PowerService.percentage / 100, charging: PowerService.charging,
        timeText: PowerService.formattedTimeRemaining()
    } : undefined

    readonly property var network: has("network") ? {
        connected: NetworkService.connected, name: NetworkService.ssid || NetworkService.connectionType,
        down: Math.max(0, SystemMonitorService.netRxBps), up: Math.max(0, SystemMonitorService.netTxBps)
    } : undefined

    readonly property var theme: ({
        accent: Colors.accent.toString(), onAccent: Colors.onAccent.toString(), text: Colors.textPrimary.toString(),
        textSecondary: Colors.textSecondary.toString(), textMuted: Colors.textMuted.toString(),
        surface: Colors.surface.toString(), border: Colors.border.toString(), danger: Colors.danger.toString(),
        font: Typography.family, radius: Metrics.radiusLg
    })
}
