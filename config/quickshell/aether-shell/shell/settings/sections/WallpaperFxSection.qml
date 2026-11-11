import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"

// Settings → Wallpaper effects: transitions, depth/parallax, ambient
// layer, scheduling and live video.
ColumnLayout {
    spacing: Metrics.spaceLg

    SettingRow {
        label: "Wallpaper"
        description: Config.wallpaper.mode === "image" ? "Your images (Settings → Wallpaper, SUPER+W)"
            : Config.wallpaper.mode === "gradient" ? "A gradient from the current palette — no image, no GPU cost"
            : "An animated aurora from the palette (still frame when effects are reduced)"
        SegmentedControl {
            options: [{ value: "image", label: "Image" }, { value: "gradient", label: "Gradient" }, { value: "aurora", label: "Aurora" }]
            current: Config.wallpaper.mode
            onSelected: function(v) { Config.wallpaper.mode = v; }
        }
    }
    SettingRow {
        label: "Transition"
        description: "Played when the wallpaper changes. Shader transitions fall back to a fade without shader support"
        ChipGroup {
            Layout.maximumWidth: 380
            options: [{ value: "none", label: "None" }, { value: "fade", label: "Fade" }, { value: "zoom", label: "Zoom" }, { value: "slide", label: "Slide" },
                      { value: "wipe", label: "Wipe" }, { value: "circle", label: "Circle" }, { value: "dissolve", label: "Dissolve" },
                      { value: "blinds", label: "Blinds" }, { value: "random", label: "Random" }]
            current: Config.wallpaper.transition
            onSelected: function(v) { Config.wallpaper.transition = v; }
        }
    }
    SettingRow {
        label: "Transition length"
        description: (Config.wallpaper.transitionDuration / 1000).toFixed(1) + " s"
        Slider { implicitWidth: 180; from: 200; to: 3000; value: Config.wallpaper.transitionDuration; format: function(v) { return (v / 1000).toFixed(1) + " s"; }; onMoved: function(v) { Config.wallpaper.transitionDuration = Math.round(v / 50) * 50; } }
    }
    RowLayout {
        Item { Layout.fillWidth: true }
        ChipGroup { options: [{ value: "go", label: "Preview: next wallpaper" }]; current: ""; onSelected: WallpaperService.nextWallpaper() }
    }

    SectionLabel { text: "Depth"; Layout.topMargin: Metrics.spaceSm }
    SettingRow {
        label: "Pointer parallax"
        description: WallpaperService.depthFor(WallpaperService.currentWallpaper)
            ? "This wallpaper has a depth map: near objects move more than far ones"
            : "No depth map for this wallpaper (add <name>.depth.png beside it): the whole picture shifts as one plane"
        Switch { checked: Config.wallpaper.parallax; onToggled: function(v) { Config.wallpaper.parallax = v; } }
    }
    SettingRow {
        visible: Config.wallpaper.parallax
        label: "Depth strength"
        Slider { implicitWidth: 180; from: 0; to: 1; value: Config.wallpaper.parallaxStrength; onMoved: function(v) { Config.wallpaper.parallaxStrength = Math.round(v * 100) / 100; } }
    }

    SectionLabel { text: "Ambient layer"; Layout.topMargin: Metrics.spaceSm }
    SettingRow {
        label: "Effect"
        description: PerformanceService.particles || Config.wallpaper.ambient === "none" || Config.wallpaper.ambient === "aurora"
            ? "Paused automatically while a fullscreen app is focused"
            : "Particles need Ultra quality and Effects → Ambient particles"
        ChipGroup {
            options: [{ value: "none", label: "None" }, { value: "stars", label: "Stars" }, { value: "snow", label: "Snow" },
                      { value: "rain", label: "Rain" }, { value: "dust", label: "Dust" }, { value: "aurora", label: "Aurora" }]
            current: Config.wallpaper.ambient
            onSelected: function(v) { Config.wallpaper.ambient = v; }
        }
    }
    SettingRow {
        visible: Config.wallpaper.ambient !== "none"
        label: "Density"
        Slider { implicitWidth: 180; from: 0.1; to: 1; value: Config.wallpaper.ambientDensity; onMoved: function(v) { Config.wallpaper.ambientDensity = Math.round(v * 100) / 100; } }
    }

    SectionLabel { text: "Schedule"; Layout.topMargin: Metrics.spaceSm }
    SettingRow {
        label: "Change wallpaper"
        description: Config.wallpaper.schedule === "interval" ? "Cycles your favourites (or all wallpapers) every " + Config.wallpaper.intervalMinutes + " minutes"
            : Config.wallpaper.schedule === "daynight" ? "Day wallpaper from " + Config.appearance.autoLightFrom + ":00, night wallpaper from " + Config.appearance.autoDarkFrom + ":00"
            : "Only when you choose"
        SegmentedControl {
            options: [{ value: "off", label: "Manually" }, { value: "interval", label: "Every…" }, { value: "daynight", label: "Day / night" }]
            current: Config.wallpaper.schedule
            onSelected: function(v) { Config.wallpaper.schedule = v; }
        }
    }
    SettingRow {
        visible: Config.wallpaper.schedule === "interval"
        label: "Interval"
        Slider { implicitWidth: 180; from: 5; to: 240; value: Config.wallpaper.intervalMinutes; format: function(v) { return Math.round(v) + " min"; }; onMoved: function(v) { Config.wallpaper.intervalMinutes = Math.round(v / 5) * 5; } }
    }
    RowLayout {
        visible: Config.wallpaper.schedule === "daynight"
        spacing: Metrics.spaceSm
        ChipGroup { options: [{ value: "d", label: "Use current as day wallpaper" }]; current: Config.wallpaper.dayWallpaper === WallpaperService.currentWallpaper ? "d" : ""; onSelected: Config.wallpaper.dayWallpaper = WallpaperService.currentWallpaper }
        ChipGroup { options: [{ value: "n", label: "Use current as night wallpaper" }]; current: Config.wallpaper.nightWallpaper === WallpaperService.currentWallpaper ? "n" : ""; onSelected: Config.wallpaper.nightWallpaper = WallpaperService.currentWallpaper }
    }
    SettingRow {
        label: "Favourite this wallpaper"
        description: (Config.wallpaper.favorites || []).length + " favourite(s)"
        Switch { checked: WallpaperService.isFavorite(WallpaperService.currentWallpaper); onToggled: WallpaperService.toggleFavorite(WallpaperService.currentWallpaper) }
    }

    SectionLabel { text: "Live video wallpaper"; Layout.topMargin: Metrics.spaceSm }
    Rectangle {
        Layout.fillWidth: true; implicitHeight: 34; radius: 17
        color: Colors.withAlpha(Colors.surface, 0.9); border.width: 1; border.color: videoIn.activeFocus ? Colors.accent : Colors.border
        TextInput {
            id: videoIn
            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
            verticalAlignment: TextInput.AlignVCenter
            text: Config.wallpaper.video
            color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm
            onEditingFinished: Config.wallpaper.video = text.trim()
        }
        Text { anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; visible: videoIn.text.length === 0; text: "/path/to/video.mp4 (empty = off)"; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
    }
    Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Status: " + VideoWallpaperService.state; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
    SettingRow {
        label: "Pause on battery"
        Switch { checked: Config.wallpaper.videoPauseOnBattery; onToggled: function(v) { Config.wallpaper.videoPauseOnBattery = v; } }
    }
}
