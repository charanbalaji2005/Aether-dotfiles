import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../core"
import "../../services"
import "../../components"
import "SettingsIndex.js" as SettingsIndex

// Settings (SUPER+I). Every control writes Config (persisted live to
// ~/.config/aether-shell/config.json) or calls a real backend — the
// Hyprland profile goes through `aether performance hyprland <profile>`.
Scope {
    id: root

    readonly property var accentPresets: ["#7C9CFF", "#B48CFF", "#38BDF8", "#2DD4BF", "#4ADE80", "#FBBF24", "#FB923C", "#F87171", "#F472B6"]
    readonly property var sections: [
        { id: "appearance", label: "Appearance", icon: "contrast" },
        { id: "style", label: "Style & palette", icon: "star", file: "StyleSection" },
        { id: "effects", label: "Effects & motion", icon: "bolt", file: "EffectsSection" },
        { id: "bar", label: "Bar", icon: "sliders" },
        { id: "dockisland", label: "Dock & island", icon: "grid", file: "DockIslandSection" },
        { id: "notifications", label: "Notifications", icon: "bell" },
        { id: "wallpaper", label: "Wallpaper", icon: "image" },
        { id: "wallfx", label: "Wallpaper effects", icon: "image", file: "WallpaperFxSection" },
        { id: "battery", label: "Battery", icon: "battery", file: "BatterySection" },
        { id: "lock", label: "Lock screen", icon: "lock", file: "LockSection" },
        { id: "gestures", label: "Gestures", icon: "arrow-up", file: "GesturesSection" },
        { id: "automation", label: "Automation", icon: "refresh", file: "AutomationSection" },
        { id: "profiles", label: "Profiles", icon: "display", file: "ProfilesSection" },
        { id: "terminal", label: "Terminal", icon: "code", file: "TerminalSection" },
        { id: "keyboard", label: "Keyboard", icon: "keyboard", file: "KeyboardSection" },
        { id: "mouse", label: "Mouse & touchpad", icon: "mouse", file: "MouseSection" },
        { id: "displays", label: "Displays", icon: "display", file: "DisplaysSection" },
        { id: "workspaces", label: "Workspaces", icon: "grid", file: "WorkspacesSection" },
        { id: "widgets", label: "Widgets", icon: "widgets", file: "WidgetsSection" },
        { id: "gpu", label: "GPU & rendering", icon: "gpu", file: "GpuSection" },
        { id: "accessibility", label: "Accessibility", icon: "search", file: "AccessibilitySection" },
        { id: "privacy", label: "Privacy & security", icon: "shield", file: "PrivacySection" },
        { id: "ai", label: "AI assistant", icon: "sparkle", file: "AiSection" },
        { id: "startup", label: "Startup apps", icon: "power", file: "StartupSection" },
        { id: "backup", label: "Backup & recovery", icon: "archive", file: "BackupSection" },
        { id: "developer", label: "Developer", icon: "code", file: "DeveloperSection" },
        { id: "performance", label: "Performance", icon: "gauge" },
        { id: "about", label: "About", icon: "activity" }
    ]

    // Hyprland profile via the CLI.
    property string hyprProfileStatus: ""
    Process {
        id: hyprProfileProc
        property string profile: ""
        property string err: ""
        stderr: StdioCollector { onStreamFinished: hyprProfileProc.err = this.text.trim() }
        // Status comes from the exit code, not from whichever stream finishes first.
        onExited: function(code) {
            if (code === 0) {
                root.currentHyprProfile = hyprProfileProc.profile;
                root.hyprProfileStatus = "Applied '" + hyprProfileProc.profile + "' profile";
            } else {
                root.hyprProfileStatus = hyprProfileProc.err.length > 0 ? hyprProfileProc.err : "Failed (exit " + code + ")";
            }
        }
    }
    // Current profile, read from the marker line the CLI writes.
    property string currentHyprProfile: ""
    Process {
        id: readHyprProfile
        command: ["sh", "-c", 'sed -n "s/^# AETHER_PROFILE=//p" "$HOME/.config/aether-shell/hypr/profile.conf" 2>/dev/null']
        stdout: StdioCollector { onStreamFinished: root.currentHyprProfile = this.text.trim() || "balanced" }
    }

    function applyHyprProfile(p) {
        hyprProfileProc.profile = p;
        root.hyprProfileStatus = "Applying…";
        hyprProfileProc.command = Paths.aether(["performance", "hyprland", p]);
        hyprProfileProc.running = true;
    }

    PopupPanel {
        id: panel
        layerNamespace: "aether-settings"
        placement: "center"
        cardWidth: Math.min(880, (screen ? screen.width : 1280) - 120)
        cardHeight: Math.min(640, (screen ? screen.height : 900) - 120)

        property string activeSection: "appearance"
        property string searchText: ""
        readonly property var filteredSections: {
            if (searchText.trim().length < 2) return root.sections;
            const hits = SettingsIndex.search(searchText, 12).map(function(e) { return e.id; });
            const q = searchText.toLowerCase();
            return root.sections.filter(function(s) { return hits.indexOf(s.id) >= 0 || s.label.toLowerCase().indexOf(q) >= 0; });
        }

        onOpened: {
            HardwareService.ensureLoaded();
            readHyprProfile.running = true;
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ── Sidebar ────────────────────────────────────────────────
            ColumnLayout {
                Layout.preferredWidth: 190
                Layout.fillHeight: true
                Layout.margins: Metrics.spaceMd
                spacing: Metrics.spaceXs

                Text {
                    text: "Settings"
                    color: Colors.textPrimary
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeXl
                    font.weight: Typography.weightBold
                    Layout.leftMargin: Metrics.spaceSm
                    Layout.bottomMargin: Metrics.spaceSm
                }

                // Search: filters the sections by title and the words inside
                // them (theme/Palettes, "refresh rate", "api key", …).
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 16
                    color: Colors.withAlpha(Colors.surface, 0.9)
                    border.width: 1
                    border.color: settingsSearch.activeFocus ? Colors.accent : Colors.border
                    TextInput {
                        id: settingsSearch
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm
                        onTextChanged: { panel.searchText = text; const hit = panel.filteredSections[0]; if (hit && text.length >= 2) panel.activeSection = hit.id; }
                        Keys.onEscapePressed: text = ""
                        Accessible.role: Accessible.EditableText
                        Accessible.name: "Search settings"
                    }
                    Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; visible: settingsSearch.text.length === 0
                           text: "Search settings"; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Metrics.spaceXxs
                    boundsBehavior: Flickable.StopAtBounds
                    model: panel.filteredSections
                    delegate: Rectangle {
                        id: navItem
                        width: ListView.view.width
                        required property var modelData
                        readonly property bool current: panel.activeSection === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: Metrics.radiusMd
                        color: current ? Colors.accentSoft : (navArea.containsMouse ? Colors.surfaceHover : "transparent")
                        Behavior on color { enabled: !Motion.reducedMotion; ColorAnimation { duration: Motion.fast } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Metrics.spaceMd
                            spacing: Metrics.spaceSm
                            AetherIcon { width: 15; height: 15; name: navItem.modelData.icon; color: navItem.current ? Colors.accent : Colors.textSecondary }
                            Text {
                                text: navItem.modelData.label
                                color: navItem.current ? Colors.accent : Colors.textSecondary
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeSm
                                font.weight: Typography.weightMedium
                                Layout.fillWidth: true
                            }
                        }
                        MouseArea {
                            id: navArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.activeSection = navItem.modelData.id
                        }
                    }
                }
            }

            Rectangle { Layout.preferredWidth: Metrics.borderWidth; Layout.fillHeight: true; color: Colors.border }

            // ── Content ────────────────────────────────────────────────
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: content.implicitHeight + Metrics.spaceXl * 2
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: content
                    x: Metrics.spaceXl
                    y: Metrics.spaceXl
                    width: parent.width - Metrics.spaceXl * 2
                    spacing: Metrics.spaceLg

                    Text {
                        text: root.sections.filter(function(s) { return s.id === panel.activeSection; })[0].label
                        color: Colors.textPrimary
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeXl
                        font.weight: Typography.weightSemibold
                    }

                    // ══════════ Sections in their own files ══════════
                    // Loaded only while selected: an unopened section costs nothing.
                    Loader {
                        Layout.fillWidth: true
                        readonly property var entry: root.sections.filter(function(x) { return x.id === panel.activeSection; })[0]
                        active: panel.open && entry !== undefined && entry.file !== undefined
                        source: active ? "sections/" + entry.file + ".qml" : ""
                        onStatusChanged: if (status === Loader.Error) Logger.error("Settings", "Section " + entry.file + " failed to load")
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: panel.open && panel.activeSection === "notifications"
                        source: active ? "sections/NotificationRulesSection.qml" : ""
                        // Shown after the inline Notifications settings below.
                        z: 1
                    }

                    // ══════════ Appearance ══════════
                    ColumnLayout {
                        visible: panel.activeSection === "appearance"
                        Layout.fillWidth: true
                        spacing: Metrics.spaceLg

                        SettingRow {
                            label: "Theme"
                            description: Config.appearance.theme === "auto"
                                ? "Light from " + Config.appearance.autoLightFrom + ":00, dark from " + Config.appearance.autoDarkFrom + ":00"
                                : "Applies to the shell" + (Config.appearance.syncGtk ? " and GTK apps" : "")
                            SegmentedControl {
                                options: [{ value: "dark", label: "Dark" }, { value: "light", label: "Light" }, { value: "auto", label: "Auto" }]
                                current: Config.appearance.theme
                                onSelected: function(v) { Config.appearance.theme = v; }
                            }
                        }
                        SettingRow {
                            label: "Sync GTK apps"
                            description: "Sets the GTK / libadwaita colour scheme with gsettings"
                            Switch { checked: Config.appearance.syncGtk; onToggled: function(v) { Config.appearance.syncGtk = v; } }
                        }

                        SettingRow {
                            label: "Accent colour"
                            description: Config.appearance.accentMode === "wallpaper"
                                ? (ThemeService.accentError.length > 0 ? ThemeService.accentError : "Derived from the current wallpaper")
                                : "Used across the bar, panels and highlights"
                            SegmentedControl {
                                options: [{ value: "manual", label: "Manual" }, { value: "wallpaper", label: "From wallpaper" }]
                                current: Config.appearance.accentMode
                                onSelected: function(v) { Config.appearance.accentMode = v; }
                            }
                        }
                        Flow {
                            visible: Config.appearance.accentMode !== "wallpaper"
                            Layout.fillWidth: true
                            spacing: Metrics.spaceSm
                            Repeater {
                                model: root.accentPresets
                                delegate: ColorSwatch {
                                    required property string modelData
                                    swatchColor: modelData
                                    selected: Config.appearance.accent.toLowerCase() === modelData.toLowerCase()
                                    onClicked: Config.appearance.accent = modelData
                                }
                            }
                            Rectangle {
                                width: 96; height: 28
                                radius: 14
                                color: Colors.surface
                                border.width: 1
                                border.color: hexInput.activeFocus ? Colors.accent : Colors.border
                                TextInput {
                                    id: hexInput
                                    anchors.fill: parent
                                    anchors.leftMargin: Metrics.spaceSm
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Colors.textPrimary
                                    font.family: Typography.familyMono
                                    font.pixelSize: Typography.sizeXs + 1
                                    maximumLength: 7
                                    text: Config.appearance.accent
                                    validator: RegularExpressionValidator { regularExpression: /#?[0-9A-Fa-f]{0,6}/ }
                                    onAccepted: {
                                        const v = (text.charAt(0) === "#" ? text : "#" + text).toUpperCase();
                                        if (/^#[0-9A-F]{6}$/.test(v)) Config.appearance.accent = v;
                                    }
                                }
                            }
                        }
                        Text {
                            visible: Config.appearance.accentMode === "wallpaper" && ThemeService.extracting
                            text: "Reading wallpaper colours…"
                            color: Colors.textMuted
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeXs
                        }

                        SettingRow {
                            label: "Panel transparency"
                            description: "Opacity of popups and panels: " + Math.round(Config.appearance.panelOpacity * 100) + "%"
                            Slider {
                                width: 160
                                from: 0.5; to: 1.0
                                value: Config.appearance.panelOpacity
                                onMoved: function(v) { Config.appearance.panelOpacity = Math.round(v * 100) / 100; }
                            }
                        }
                        SettingRow {
                            label: "Background blur"
                            description: "Compositor blur behind windows and panels. 'Profile' follows the Hyprland performance profile."
                            SegmentedControl {
                                options: [{ value: "profile", label: "Profile" }, { value: "on", label: "On" }, { value: "off", label: "Off" }]
                                current: Config.appearance.compositorBlur
                                onSelected: function(v) { Config.appearance.compositorBlur = v; }
                            }
                        }
                        SettingRow {
                            label: "Animation speed"
                            description: Config.general.reducedMotion ? "Animations are off (reduced motion)" : Config.general.animationSpeed.toFixed(2) + "×"
                            Slider {
                                width: 160
                                from: 0.5; to: 2.0
                                value: Config.general.animationSpeed
                                onMoved: function(v) { Config.general.animationSpeed = Math.round(v * 4) / 4; }
                            }
                        }
                        SettingRow {
                            label: "Reduced motion"
                            description: "Turns off shell animations (accessibility)"
                            Switch { checked: Config.general.reducedMotion; onToggled: function(v) { Config.general.reducedMotion = v; } }
                        }
                        SettingRow {
                            label: "24-hour clock"
                            Switch { checked: Config.general.use24Hour; onToggled: function(v) { Config.general.use24Hour = v; } }
                        }
                    }

                    // ══════════ Bar ══════════
                    ColumnLayout {
                        visible: panel.activeSection === "bar"
                        Layout.fillWidth: true
                        spacing: Metrics.spaceLg

                        SettingRow {
                            label: "Style"
                            description: "Full width, floating island, or a centred dock"
                            SegmentedControl {
                                options: [{ value: "full", label: "Full" }, { value: "floating", label: "Floating" }, { value: "dock", label: "Dock" }]
                                current: Config.bar.style
                                onSelected: function(v) { Config.bar.style = v; }
                            }
                        }
                        SettingRow {
                            label: "Position"
                            SegmentedControl {
                                options: [{ value: "top", label: "Top" }, { value: "bottom", label: "Bottom" }]
                                current: Config.bar.position
                                onSelected: function(v) { Config.bar.position = v; }
                            }
                        }
                        SettingRow {
                            label: "Height"
                            description: Config.bar.height + " px"
                            Slider {
                                width: 160
                                from: 28; to: 56
                                value: Config.bar.height
                                onMoved: function(v) { Config.bar.height = Math.round(v); }
                            }
                        }
                        SettingRow {
                            label: "Bar opacity"
                            description: Math.round(Config.appearance.barOpacity * 100) + "%"
                            Slider {
                                width: 160
                                from: 0.3; to: 1.0
                                value: Config.appearance.barOpacity
                                onMoved: function(v) { Config.appearance.barOpacity = Math.round(v * 100) / 100; }
                            }
                        }

                        SectionLabel { text: "Modules" }
                        Repeater {
                            model: [
                                { label: "Launcher button", key: "showLauncher" },
                                { label: "Active window title", key: "showActiveWindow" },
                                { label: "CPU / RAM / GPU usage", key: "showStats" },
                                { label: "Temperatures", key: "showTemperatures" },
                                { label: "Network speed", key: "showNetSpeed" },
                                { label: "System tray", key: "showTray" },
                                { label: "Media", key: "showMedia" },
                                { label: "Bluetooth", key: "showBluetooth" },
                                { label: "Network", key: "showNetwork" },
                                { label: "Volume", key: "showAudio" },
                                { label: "Microphone", key: "showMicrophone" },
                                { label: "Battery", key: "showBattery" },
                                { label: "Notifications", key: "showNotifications" }
                            ]
                            delegate: SettingRow {
                                required property var modelData
                                label: modelData.label
                                Switch {
                                    checked: Config.bar[modelData.key] === true
                                    onToggled: function(v) { Config.bar[modelData.key] = v; }
                                }
                            }
                        }
                    }

                    // ══════════ Notifications ══════════
                    ColumnLayout {
                        visible: panel.activeSection === "notifications"
                        Layout.fillWidth: true
                        spacing: Metrics.spaceLg

                        SettingRow {
                            label: "Do Not Disturb"
                            description: "Silences toasts; critical alerts still show. Everything is kept in the history."
                            Switch { checked: NotificationService.doNotDisturb; onToggled: NotificationService.toggleDnd() }
                        }
                        SettingRow {
                            label: "Group by application"
                            Switch { checked: Config.notifications.groupByApp; onToggled: function(v) { Config.notifications.groupByApp = v; } }
                        }
                        SettingRow {
                            label: "Timeout"
                            description: (Config.notifications.timeoutNormal / 1000).toFixed(0) + " s (low priority: " + (Config.notifications.timeoutLow / 1000).toFixed(0) + " s). Critical notifications stay until dismissed."
                            Slider {
                                width: 160
                                from: 2000; to: 20000
                                value: Config.notifications.timeoutNormal
                                onMoved: function(v) {
                                    Config.notifications.timeoutNormal = Math.round(v / 1000) * 1000;
                                    Config.notifications.timeoutLow = Math.max(2000, Math.round(v * 0.66 / 1000) * 1000);
                                }
                            }
                        }
                        SettingRow {
                            label: "Visible at once"
                            description: Config.notifications.maxVisible + " toasts"
                            Slider {
                                width: 160
                                from: 1; to: 8
                                value: Config.notifications.maxVisible
                                onMoved: function(v) { Config.notifications.maxVisible = Math.round(v); }
                            }
                        }
                    }

                    // ══════════ Wallpaper ══════════
                    ColumnLayout {
                        visible: panel.activeSection === "wallpaper"
                        Layout.fillWidth: true
                        spacing: Metrics.spaceLg

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Metrics.spaceMd
                            Rectangle {
                                Layout.preferredWidth: 192
                                Layout.preferredHeight: 108
                                radius: Metrics.radiusMd
                                color: Colors.surface
                                border.color: Colors.border
                                border.width: 1
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    source: WallpaperService.currentWallpaper ? ("file://" + WallpaperService.currentWallpaper) : ""
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize.width: 384
                                    asynchronous: true
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Metrics.spaceSm
                                Text {
                                    text: WallpaperService.currentTitle || "No wallpaper active"
                                    color: Colors.textPrimary
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeMd
                                    font.weight: Typography.weightMedium
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: WallpaperService.wallpapers.length + " wallpapers available"
                                    color: Colors.textMuted
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeXs
                                }
                                RowLayout {
                                    spacing: Metrics.spaceSm
                                    IconButton { icon: "image"; active: true; onClicked: { panel.hide(); EventBus.wallpaperPickerRequested(); } }
                                    IconButton { icon: "refresh"; onClicked: WallpaperService.randomWallpaper() }
                                    IconButton { icon: "chevron-right"; onClicked: WallpaperService.nextWallpaper() }
                                }
                            }
                        }

                        SettingRow {
                            label: "Dim"
                            description: Math.round(Config.appearance.wallpaperDim * 100) + "% darker, for text contrast"
                            Slider {
                                width: 160
                                from: 0; to: 0.7
                                value: Config.appearance.wallpaperDim
                                onMoved: function(v) { Config.appearance.wallpaperDim = Math.round(v * 100) / 100; }
                            }
                        }
                        SettingRow {
                            label: "Blur"
                            description: Config.appearance.wallpaperBlur > 0 ? Math.round(Config.appearance.wallpaperBlur * 100) + "% — rendered once per wallpaper, not every frame" : "Off"
                            Slider {
                                width: 160
                                from: 0; to: 1
                                value: Config.appearance.wallpaperBlur
                                onMoved: function(v) { Config.appearance.wallpaperBlur = Math.round(v * 20) / 20; }
                            }
                        }
                        SettingRow {
                            label: "Animated wallpapers"
                            description: "Play GIF wallpapers. Paused automatically on battery and under reduced motion."
                            Switch { checked: Config.appearance.animatedWallpapers; onToggled: function(v) { Config.appearance.animatedWallpapers = v; } }
                        }
                        SettingRow {
                            label: "Accent from wallpaper"
                            description: "Requires ImageMagick"
                            Switch {
                                checked: Config.appearance.accentMode === "wallpaper"
                                onToggled: function(v) { Config.appearance.accentMode = v ? "wallpaper" : "manual"; }
                            }
                        }
                        Text {
                            text: "Per-display wallpapers: open the picker and right-click a wallpaper to set it for the current display only."
                            color: Colors.textMuted
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeXs
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    // ══════════ Performance ══════════
                    ColumnLayout {
                        visible: panel.activeSection === "performance"
                        Layout.fillWidth: true
                        spacing: Metrics.spaceLg

                        SettingRow {
                            label: "Power profile"
                            description: PowerProfileService.available
                                ? "System-wide CPU/firmware power policy (powerprofilesctl)"
                                : "Unavailable — install power-profiles-daemon (or tuned-ppd)"
                            SegmentedControl {
                                visible: PowerProfileService.available
                                options: PowerProfileService.profiles.map(function(p) {
                                    return { value: p, label: p === "power-saver" ? "Saver" : p === "performance" ? "Performance" : "Balanced" };
                                })
                                current: PowerProfileService.active
                                onSelected: function(v) { PowerProfileService.set(v); }
                            }
                        }

                        SettingRow {
                            label: "Hyprland profile"
                            description: root.hyprProfileStatus.length > 0 ? root.hyprProfileStatus
                                : "Compositor effects: blur, shadows, animations, tearing"
                            SegmentedControl {
                                options: [{ value: "quality", label: "Quality" }, { value: "balanced", label: "Balanced" },
                                          { value: "low-latency", label: "Low latency" }, { value: "battery", label: "Battery" }]
                                current: root.currentHyprProfile
                                onSelected: function(v) { root.applyHyprProfile(v); }
                            }
                        }

                        SettingRow {
                            label: "Telemetry interval"
                            description: "How often CPU/GPU/RAM are sampled: " + (Config.performance.telemetryInterval / 1000).toFixed(1) + " s. Longer = less CPU."
                            Slider {
                                width: 160
                                from: 1000; to: 5000
                                value: Config.performance.telemetryInterval
                                onMoved: function(v) { Config.performance.telemetryInterval = Math.round(v / 500) * 500; }
                            }
                        }
                        SettingRow {
                            label: "Sample less on battery"
                            description: "Halves telemetry sampling while unplugged"
                            Switch { checked: Config.performance.pauseOnBattery; onToggled: function(v) { Config.performance.pauseOnBattery = v; } }
                        }
                        SettingRow {
                            label: "Night light temperature"
                            description: Config.nightLight.temperature + " K" + (NightLightService.available ? "" : " (install hyprsunset)")
                            Slider {
                                width: 160
                                from: 2500; to: 6000
                                value: Config.nightLight.temperature
                                onMoved: function(v) { Config.nightLight.temperature = Math.round(v / 100) * 100; }
                            }
                        }
                        Text {
                            text: "AetherOS never changes CPU governors, clocks, voltages or power limits directly. For GPU drivers and diagnostics use the terminal: aether graphics verify · aether diagnostics"
                            color: Colors.textMuted
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeXs
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    // ══════════ About ══════════
                    ColumnLayout {
                        visible: panel.activeSection === "about"
                        Layout.fillWidth: true
                        spacing: Metrics.spaceSm

                        Text {
                            text: "AetherOS Shell — an independently implemented Hyprland desktop shell built on Quickshell."
                            color: Colors.textSecondary
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeSm
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: HardwareService.loaded
                            text: [HardwareService.os, HardwareService.cpuModel, HardwareService.gpus.map(function(g) { return g.name.replace(/\s*\[.*$/, ""); }).join(" + ")]
                                .filter(function(s) { return s && s.length > 0; }).join("\n")
                            color: Colors.textMuted
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeXs
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }

                        SectionLabel { text: "Service status"; Layout.topMargin: Metrics.spaceMd }

                        Repeater {
                            model: [
                                { label: "Hyprland", available: HyprlandService.available },
                                { label: "Telemetry backend (aether)", available: SystemMonitorService.source === "telemetry" },
                                { label: "Audio (PipeWire)", available: AudioService.available },
                                { label: "Battery (UPower)", available: PowerService.available },
                                { label: "Network (NetworkManager)", available: NetworkService.available },
                                { label: "Bluetooth (BlueZ)", available: BluetoothService.available },
                                { label: "Brightness (brightnessctl)", available: BrightnessService.available },
                                { label: "Night light (hyprsunset)", available: NightLightService.available },
                                { label: "Power profiles", available: PowerProfileService.available },
                                { label: "Media (MPRIS)", available: MediaService.available },
                                { label: "Clipboard (cliphist)", available: ClipboardService.available },
                                { label: "Screenshots (grim)", available: ScreenshotService.available }
                            ]

                            delegate: RowLayout {
                                id: statusRow
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Metrics.spaceSm
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    color: statusRow.modelData.available ? Colors.success : Colors.textMuted
                                }
                                Text {
                                    text: statusRow.modelData.label
                                    color: Colors.textSecondary
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeSm
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: statusRow.modelData.available ? "available" : "unavailable"
                                    color: statusRow.modelData.available ? Colors.success : Colors.textMuted
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeXs
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: EventBus
        function onSettingsRequested(section) {
            if (section && section.length > 0) panel.activeSection = section;
            panel.show();
        }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { panel.toggle(); }
        function show(): void { panel.show(); }
        function hide(): void { panel.hide(); }
    }
}
