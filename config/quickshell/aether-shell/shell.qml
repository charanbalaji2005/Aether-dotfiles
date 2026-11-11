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
import "./shell/overview"
import "./shell/island"
import "./shell/dock"
import "./shell/systemcenter"
import "./shell/gestures"
import "./shell/layouts"
import "./shell/assistant"
import "./shell/widgets"

ShellRoot {
    id: shellRoot

    // ── Theme ↔ config/service bridges ─────────────────────────────────
    // theme/ and core/ stay free of service imports; this is the one place
    // that connects them (see ARCHITECTURE.md).
    Binding { target: Colors; property: "accentInput"; value: Config.appearance.accent }
    Binding { target: Colors; property: "preferDark"; value: ThemeService.isDark }
    Binding { target: Colors; property: "palette"; value: Config.appearance.palette || "aether" }
    Binding { target: Colors; property: "userPalettes"; value: ThemeService.userPalettes }
    Binding { target: Colors; property: "glassOpacity"; value: Materials.panelOpacity }
    Binding { target: Colors; property: "highContrast"; value: Config.accessibility.highContrast }
    Binding { target: Colors; property: "colorBlind"; value: Config.accessibility.colorBlind }

    Binding { target: Materials; property: "style"; value: Config.appearance.glassStyle || "medium" }
    Binding { target: Materials; property: "customOpacity"; value: Config.appearance.panelOpacity }
    Binding { target: Materials; property: "onBattery"; value: ShellState.onBattery }

    Binding { target: Metrics; property: "scale"; value: Config.accessibility.uiScale }
    Binding { target: Metrics; property: "cornerScale"; value: Config.appearance.cornerScale }
    Binding { target: Typography; property: "scale"; value: Config.accessibility.uiScale }
    Binding { target: FocusState; property: "ringsEnabled"; value: Config.accessibility.focusRings }

    Binding { target: Motion; property: "profile"; value: Config.general.motionProfile || "smooth" }
    Binding { target: Motion; property: "reducedMotionSetting"; value: Config.general.reducedMotion }
    Binding { target: Motion; property: "userSpeed"; value: Config.general.animationSpeed }
    Binding { target: Motion; property: "springsSetting"; value: PerformanceService.springs }
    Binding { target: AnimationCoordinator; property: "refreshRate"; value: PerformanceService.refreshRate }

    // Graphics quality: decided in one place (PerformanceService).
    Binding { target: Effects; property: "tier"; value: PerformanceService.tier }
    Binding { target: Effects; property: "shaders"; value: PerformanceService.shaders }
    Binding { target: Effects; property: "glow"; value: PerformanceService.glow }
    Binding { target: Effects; property: "particles"; value: PerformanceService.particles }
    Binding { target: Effects; property: "parallax"; value: PerformanceService.parallax }
    Binding { target: Effects; property: "lightFollow"; value: PerformanceService.lightFollow }
    Binding { target: Effects; property: "ambient"; value: PerformanceService.ambient }
    Binding { target: Effects; property: "shaderDir"; value: PerformanceService.shaderDir }

    Binding { target: ShellState; property: "activeScreen"; value: HyprlandService.focusedScreen }
    Binding { target: ShellState; property: "onBattery"; value: PowerService.available && !PowerService.charging && !PowerService.fullyCharged }

    // Singletons are created on first reference. These run in the background
    // (automation rules, hypridle sync, video wallpaper lifecycle, the island
    // event queue), so reference them once at start-up.
    readonly property var _backgroundServices: [AutomationService, IdleService, VideoWallpaperService, IslandService, PerformanceService, PrivacyService, SystemSettingsService]

    WallpaperBackground {}
    WidgetLayer {}
    Bar {}
    DynamicIsland {}
    Dock {}
    EdgeGestures {}
    Launcher {}
    ControlCenter {}
    Dashboard {}
    NotificationPopup {}
    NotificationCenter {}
    ClipboardHistory {}
    ScreenshotController {}
    WallpaperPicker {}
    Overview {}
    SystemCenter {}
    LayoutPicker {}
    Assistant {}
    LockScreen {}
    PowerMenu {}
    Settings {}
    BluetoothManager {}
    OSD {}
}
