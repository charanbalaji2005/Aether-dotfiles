pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"
import "../policy/Pressure.js" as Pressure

// Decides how much visual work the shell does, and says why.
//
// Inputs:
//   * Config.effects.quality: "auto" | "eco" | "balanced" | "ultra"
//   * `aether capabilities --json` (once): hardware recommendation computed
//     from sysfs only — it never wakes a sleeping discrete GPU
//   * safe mode (AETHER_SAFE_MODE=1 from aether-shell-safe.service, or
//     `aether safe-mode on`): everything optional off, always
//   * power: on battery / power-saver profile (auto mode only)
//   * frame pacing: AnimationCoordinator.struggling — measured only while
//     the shell itself animates (auto + adaptive only)
//   * a fullscreen window: ambient work (particles, parallax, video) pauses
//
// Output: the Effects flags (bound in shell.qml) and a human-readable
// `reasons` list + `history` of automatic changes for Settings and the
// System Centre. A manual quality choice is respected except in safe mode.
Singleton {
    id: root

    // Ordered from cheapest to richest. "performance" keeps glass and quick
    // motion but drops ambient work (glow, particles, aurora, parallax) —
    // the profile for gaming or a busy GPU.
    readonly property var tiers: ["eco", "performance", "balanced", "ultra"]
    property var caps: null
    readonly property bool safeMode: Quickshell.env("AETHER_SAFE_MODE") === "1" || (caps !== null && caps.safeMode === true)

    readonly property string setting: Config.effects.quality || "auto"
    readonly property string hardwareTier: caps && caps.tier ? caps.tier : "balanced"
    readonly property bool hardwareShaders: caps === null || caps.shaders !== false
    readonly property bool fullscreen: WindowService.fullscreenActive
    readonly property bool batterySaver: PowerProfileService.batterySaver
    readonly property bool onBattery: ShellState.onBattery

    function _min(a, b) { return root.tiers.indexOf(a) <= root.tiers.indexOf(b) ? a : b; }
    function _down(t) { return root.tiers[Math.max(0, root.tiers.indexOf(t) - 1)]; }

    readonly property var decision: {
        const why = [];
        let t;
        if (root.safeMode) {
            return { tier: "eco", why: ["Safe mode: every optional effect is off (aether safe-mode off)."] };
        }
        if (root.setting !== "auto") {
            t = root.tiers.indexOf(root.setting) >= 0 ? root.setting : "balanced";
            why.push("Quality set manually to '" + t + "'.");
            return { tier: t, why: why };
        }
        t = root.hardwareTier;
        why.push(caps ? (caps.reasons && caps.reasons.length ? caps.reasons[0] : "Hardware: " + t) : "Hardware not probed yet: assuming balanced.");
        if (root.batterySaver) { t = "eco"; why.push("Power saver profile is active."); }
        else if (root.onBattery) { const b = root._min(t, "balanced"); if (b !== t) why.push("On battery: capped at balanced."); t = b; }
        if (Config.effects.gpuPressure && root.pressure.active) {
            const d = root._down(t);
            if (d !== t) why.push(root.pressure.reason + ": stepped down until it eases (hysteresis).");
            t = d;
        }
        if (Config.effects.adaptive && AnimationCoordinator.struggling) {
            const d = root._down(t);
            if (d !== t) why.push("Frames ran late during animations (" + AnimationCoordinator.lateFrames + " of " + AnimationCoordinator.windowSize + "): stepped down.");
            t = d;
        }
        return { tier: t, why: why };
    }

    readonly property string tier: decision.tier
    readonly property var reasons: decision.why.concat(root.fullscreen ? ["A fullscreen window is active: ambient effects paused."] : [])

    readonly property bool rich: root.tier === "balanced" || root.tier === "ultra"
    readonly property bool shaders: !root.safeMode && root.hardwareShaders && Config.effects.shaders && root.tier !== "eco"
    readonly property bool glow: !root.safeMode && Config.effects.glow && root.rich
    readonly property bool particles: !root.safeMode && Config.effects.particles && root.tier === "ultra" && !root.fullscreen
    readonly property bool parallax: !root.safeMode && Config.wallpaper.parallax && root.rich && !root.fullscreen
    readonly property bool lightFollow: !root.safeMode && root.rich
    readonly property bool ambient: !root.safeMode && root.rich && !root.fullscreen
    readonly property bool springs: !root.safeMode && Config.effects.springs
    readonly property bool videoAllowed: !root.safeMode && !(Config.wallpaper.videoPauseOnBattery && root.onBattery) && !root.batterySaver
    readonly property bool automationAllowed: !root.safeMode
    readonly property string shaderDir: caps && caps.shaderDir ? caps.shaderDir : ""

    // GPU pressure, from the telemetry of the GPU that draws the desktop.
    property var pressure: Pressure.create({})
    readonly property var _desktopGpu: {
        const gpus = SystemMonitorService.gpus || [];
        if (root.caps && root.caps.desktopGpu) {
            const match = gpus.find(function(g) { return g.name === root.caps.desktopGpu.name; });
            if (match) return match;
        }
        return gpus.find(function(g) { return g.state === "active"; }) || null;
    }
    Connections {
        target: SystemMonitorService
        function onSampled() {
            if (!Config.effects.gpuPressure) { if (root.pressure.active) root.pressure = Pressure.create({}); return; }
            const p = Object.assign({}, root.pressure, { vramThreshold: Config.effects.vramThreshold, gpuThreshold: Config.effects.gpuThreshold });
            const next = Pressure.step(p, root._desktopGpu);
            if (next.active !== root.pressure.active && next.active)
                EventBus.islandEvent("info", { text: "Effects reduced: " + next.reason });
            root.pressure = next;
        }
    }

    // History of automatic tier changes (newest first), for the UI.
    property var history: []
    property string _lastTier: ""
    onTierChanged: {
        if (root._lastTier.length > 0 && root._lastTier !== root.tier) {
            const entry = { time: Qt.formatDateTime(new Date(), "hh:mm:ss"), from: root._lastTier, to: root.tier, why: root.reasons.join(" ") };
            root.history = [entry].concat(root.history).slice(0, 30);
            Logger.info("PerformanceService", "quality " + entry.from + " → " + entry.to + ": " + entry.why);
        }
        root._lastTier = root.tier;
    }

    Process {
        id: probe
        command: Paths.aether(["capabilities", "--json"])
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.caps = JSON.parse(this.text); }
                catch (e) { Logger.warn("PerformanceService", "aether capabilities returned no JSON; assuming balanced"); }
            }
        }
    }

    function reprobe() { probe.running = true; }

    // Refresh rate of the focused monitor feeds the frame-pacing budget.
    readonly property real refreshRate: HyprlandService.focusedMonitor && HyprlandService.focusedMonitor.lastIpcObject
        ? (HyprlandService.focusedMonitor.lastIpcObject.refreshRate || 60) : 60

    Component.onCompleted: {
        probe.running = true;
        root._lastTier = root.tier;
    }
}
