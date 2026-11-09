import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// Control centre (SUPER+A, or the sliders button in the bar).
//
// Every control is backed by a real system interface through its service:
//   Wi-Fi           nmcli                    (NetworkService)
//   Bluetooth       BlueZ                    (BluetoothService)
//   Volume / mic    PipeWire + wpctl         (AudioService)
//   Brightness      brightnessctl            (BrightnessService)
//   Night light     hyprsunset               (NightLightService)
//   Power modes     powerprofilesctl         (PowerProfileService)
//   Theme / DND     shell config             (Config)
//   Displays        hyprctl                  (DisplayService)
// A tile whose backend isn't present is disabled and says why.
Scope {
    id: root

    PopupPanel {
        id: panel
        layerNamespace: "aether-controlcenter"
        placement: "top-right"
        cardWidth: Metrics.controlCenterWidth
        cardHeight: Math.min(pages.implicitHeight + Metrics.spaceLg * 2, (screen ? screen.height : 900) - 120)

        property string page: "main"

        onOpened: {
            page = "main";
            NetworkService.refresh();
            BrightnessService.refresh();
            DisplayService.refresh();
        }

        Item {
            id: pages
            anchors.fill: parent
            anchors.margins: Metrics.spaceLg
            implicitHeight: panel.page === "main" ? mainPage.implicitHeight
                : panel.page === "wifi" ? wifiPage.implicitHeight
                : panel.page === "audio" ? audioPage.implicitHeight
                : displayPage.implicitHeight

            // ════════════════════════ MAIN ════════════════════════════
            ColumnLayout {
                id: mainPage
                width: parent.width
                spacing: Metrics.spaceMd
                visible: opacity > 0
                opacity: panel.page === "main" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                // Header: user · uptime · settings / lock / power
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceSm

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: (Quickshell.env("USER") || "AetherOS")
                            color: Colors.textPrimary
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeLg
                            font.weight: Typography.weightSemibold
                        }
                        Text {
                            text: SystemMonitorService.uptimeSeconds >= 0
                                ? "Up " + SystemMonitorService.formatUptime(SystemMonitorService.uptimeSeconds)
                                : "AetherOS"
                            color: Colors.textMuted
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeXs
                        }
                    }
                    IconButton { icon: "gear"; onClicked: { panel.hide(); EventBus.settingsRequested(""); } }
                    IconButton { icon: "lock"; onClicked: { panel.hide(); SessionService.lock(); } }
                    IconButton { icon: "power"; onClicked: { panel.hide(); EventBus.powerMenuRequested(); } }
                }

                // Quick tiles
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: Metrics.spaceSm
                    columnSpacing: Metrics.spaceSm

                    ToggleTile {
                        icon: NetworkService.wifiEnabled ? "wifi" : "wifi-off"
                        title: "Wi-Fi"
                        subtitle: !NetworkService.available ? "NetworkManager unavailable"
                            : !NetworkService.wifiHardwareAvailable ? "No Wi-Fi adapter"
                            : !NetworkService.wifiEnabled ? "Off"
                            : NetworkService.ssid.length > 0 ? NetworkService.ssid : "Not connected"
                        available: NetworkService.available && NetworkService.wifiHardwareAvailable
                        active: NetworkService.wifiEnabled
                        expandable: true
                        onToggled: NetworkService.setWifiEnabled(!NetworkService.wifiEnabled)
                        onExpand: { panel.page = "wifi"; NetworkService.refreshNetworks(true); }
                    }
                    ToggleTile {
                        icon: "bluetooth"
                        title: "Bluetooth"
                        subtitle: !BluetoothService.available ? "No adapter" : BluetoothService.enabled ? "On" : "Off"
                        available: BluetoothService.available
                        active: BluetoothService.enabled
                        expandable: true
                        onToggled: BluetoothService.toggle()
                        onExpand: { panel.hide(); EventBus.bluetoothManagerRequested(); }
                    }
                    ToggleTile {
                        icon: NotificationService.doNotDisturb ? "bell-off" : "bell"
                        title: "Do Not Disturb"
                        subtitle: NotificationService.doNotDisturb ? "Only critical alerts" : "Off"
                        active: NotificationService.doNotDisturb
                        onToggled: NotificationService.toggleDnd()
                    }
                    ToggleTile {
                        icon: "moon"
                        title: "Night Light"
                        subtitle: !NightLightService.available ? "Install hyprsunset"
                            : NightLightService.active ? NightLightService.temperature + " K" : "Off"
                        available: NightLightService.available
                        active: NightLightService.active
                        onToggled: NightLightService.toggle()
                    }
                    ToggleTile {
                        icon: "contrast"
                        title: "Dark Mode"
                        subtitle: Config.appearance.theme === "auto" ? "Automatic" : (ThemeService.isDark ? "On" : "Off")
                        active: ThemeService.isDark
                        onToggled: Config.appearance.theme = ThemeService.isDark ? "light" : "dark"
                    }
                    ToggleTile {
                        icon: AudioService.inputMuted ? "mic-off" : "mic"
                        title: "Microphone"
                        subtitle: !AudioService.inputAvailable ? "No input device" : AudioService.inputMuted ? "Muted" : "On"
                        available: AudioService.inputAvailable
                        active: AudioService.inputAvailable && !AudioService.inputMuted
                        onToggled: AudioService.toggleInputMute()
                    }
                    ToggleTile {
                        icon: "leaf"
                        title: "Battery Saver"
                        subtitle: !PowerProfileService.available ? "power-profiles-daemon not running"
                            : PowerProfileService.batterySaver ? "Power saver profile" : "Off"
                        available: PowerProfileService.available && PowerProfileService.has("power-saver")
                        active: PowerProfileService.batterySaver
                        onToggled: PowerProfileService.toggleBatterySaver()
                    }
                    ToggleTile {
                        icon: "bolt"
                        title: "Performance"
                        subtitle: !PowerProfileService.available ? "power-profiles-daemon not running"
                            : !PowerProfileService.has("performance") ? "Not offered by this CPU"
                            : PowerProfileService.performanceMode ? "Performance profile" : "Balanced"
                        available: PowerProfileService.available && PowerProfileService.has("performance")
                        active: PowerProfileService.performanceMode
                        onToggled: PowerProfileService.togglePerformance()
                    }
                }

                // Sliders
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceSm

                    SliderRow {
                        visible: AudioService.available
                        icon: AudioService.muted ? "volume-mute" : (AudioService.volume > 0.5 ? "volume-high" : "volume-low")
                        value: AudioService.volume
                        valueText: AudioService.muted ? "Muted" : Math.round(AudioService.volume * 100) + "%"
                        onIconClicked: AudioService.toggleMute()
                        onMoved: function(v) { AudioService.setVolume(v); }
                        trailingIcon: "chevron-right"
                        onTrailingClicked: panel.page = "audio"
                    }
                    SliderRow {
                        visible: AudioService.inputAvailable
                        icon: AudioService.inputMuted ? "mic-off" : "mic"
                        value: AudioService.inputVolume
                        valueText: AudioService.inputMuted ? "Muted" : Math.round(AudioService.inputVolume * 100) + "%"
                        onIconClicked: AudioService.toggleInputMute()
                        onMoved: function(v) { AudioService.setInputVolume(v); }
                    }
                    SliderRow {
                        visible: BrightnessService.available
                        icon: "sun"
                        value: BrightnessService.value
                        valueText: Math.round(BrightnessService.value * 100) + "%"
                        onMoved: function(v) { BrightnessService.set(v); }
                    }
                }

                // Media mini-player
                Rectangle {
                    visible: MediaService.available
                    Layout.fillWidth: true
                    implicitHeight: 56
                    radius: Metrics.radiusLg
                    color: Colors.withAlpha(Colors.surface, Colors.dark ? 0.7 : 0.9)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Metrics.spaceMd
                        anchors.rightMargin: Metrics.spaceSm
                        spacing: Metrics.spaceSm
                        AetherIcon { width: Metrics.iconLg; height: Metrics.iconLg; name: "music"; color: Colors.accent }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: MediaService.title || "Unknown track"
                                color: Colors.textPrimary
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeSm
                                font.weight: Typography.weightMedium
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: MediaService.artist
                                visible: text.length > 0
                                color: Colors.textMuted
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeXs
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        IconButton { icon: "prev"; iconSize: 12; onClicked: MediaService.previous() }
                        IconButton { icon: MediaService.playing ? "pause" : "play"; iconSize: 12; active: true; onClicked: MediaService.playPause() }
                        IconButton { icon: "next"; iconSize: 12; onClicked: MediaService.next() }
                    }
                }

                // Footer: battery · wallpaper · display
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceSm

                    AetherIcon {
                        visible: PowerService.available
                        width: 18; height: 12
                        name: PowerService.charging ? "battery-charging" : "battery"
                        batteryLevel: PowerService.percentage / 100
                        color: PowerService.percentage <= 15 && !PowerService.charging ? Colors.danger : Colors.textSecondary
                    }
                    Text {
                        visible: PowerService.available
                        text: Math.round(PowerService.percentage) + "%" + (PowerService.formattedTimeRemaining().length > 0
                            ? " · " + PowerService.formattedTimeRemaining() + (PowerService.charging ? " to full" : " left") : "")
                        color: Colors.textSecondary
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeXs
                    }
                    Item { Layout.fillWidth: true }
                    IconButton { icon: "image"; onClicked: { panel.hide(); EventBus.wallpaperPickerRequested(); } }
                    IconButton { icon: "display"; visible: DisplayService.available; onClicked: panel.page = "display" }
                    IconButton { icon: "activity"; onClicked: { panel.hide(); EventBus.dashboardRequested(); } }
                }
            }

            // ════════════════════════ WI-FI ═══════════════════════════
            ColumnLayout {
                id: wifiPage
                width: parent.width
                spacing: Metrics.spaceMd
                visible: opacity > 0
                opacity: panel.page === "wifi" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                property string pendingSsid: ""

                PageHeader {
                    title: "Wi-Fi"
                    onBack: panel.page = "main"
                    Spinner { visible: NetworkService.scanning || NetworkService.busySsid.length > 0; Layout.alignment: Qt.AlignVCenter }
                    IconButton { icon: "refresh"; onClicked: NetworkService.refreshNetworks(true) }
                    Switch {
                        Layout.alignment: Qt.AlignVCenter
                        checked: NetworkService.wifiEnabled
                        onToggled: function(on) { NetworkService.setWifiEnabled(on); }
                    }
                }

                Text {
                    visible: NetworkService.lastError.length > 0
                    text: NetworkService.lastError
                    color: Colors.danger
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeXs
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Text {
                    visible: !NetworkService.wifiEnabled
                    text: "Wi-Fi is off."
                    color: Colors.textMuted
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeSm
                }

                ListView {
                    id: netList
                    visible: NetworkService.wifiEnabled
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(64, Math.min(contentHeight, 360))
                    clip: true
                    spacing: 2
                    model: NetworkService.networks
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: net
                        required property var modelData
                        readonly property bool secure: modelData.security.length > 0 && modelData.security !== "--"
                        readonly property bool expanded: wifiPage.pendingSsid === modelData.ssid
                        width: netList.width
                        height: expanded ? 96 : 44
                        radius: Metrics.radiusMd
                        color: modelData.active ? Colors.accentSoft : (rowArea.containsMouse ? Colors.surfaceHover : "transparent")
                        Behavior on height { enabled: !Motion.reducedMotion; NumberAnimation { duration: Motion.fast } }
                        clip: true

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (net.modelData.active) return;
                                if (net.secure && !net.modelData.known) {
                                    wifiPage.pendingSsid = net.expanded ? "" : net.modelData.ssid;
                                } else {
                                    NetworkService.connectTo(net.modelData.ssid, "");
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Metrics.spaceMd
                            anchors.rightMargin: Metrics.spaceSm
                            anchors.topMargin: 6
                            anchors.bottomMargin: 6
                            spacing: Metrics.spaceSm

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 32
                                spacing: Metrics.spaceSm
                                AetherIcon {
                                    width: 16; height: 16
                                    name: "wifi"
                                    level: net.modelData.signal >= 70 ? 3 : net.modelData.signal >= 45 ? 2 : 1
                                    color: net.modelData.active ? Colors.accent : Colors.textPrimary
                                }
                                Text {
                                    text: net.modelData.ssid
                                    color: Colors.textPrimary
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeSm
                                    font.weight: net.modelData.active ? Typography.weightSemibold : Typography.weightRegular
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                AetherIcon { visible: net.secure; width: 12; height: 12; name: "lock"; color: Colors.textMuted }
                                Text {
                                    text: net.modelData.active ? "Connected" : (net.modelData.known ? "Saved" : "")
                                    visible: text.length > 0
                                    color: net.modelData.active ? Colors.accent : Colors.textMuted
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeXs
                                }
                                IconButton {
                                    visible: net.modelData.active
                                    icon: "close"; iconSize: 12; implicitWidth: 26; implicitHeight: 26
                                    onClicked: NetworkService.disconnect()
                                }
                                IconButton {
                                    visible: net.modelData.known && !net.modelData.active
                                    icon: "trash"; iconSize: 12; implicitWidth: 26; implicitHeight: 26
                                    onClicked: NetworkService.forget(net.modelData.ssid)
                                }
                            }

                            RowLayout {
                                visible: net.expanded
                                Layout.fillWidth: true
                                spacing: Metrics.spaceSm
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 34
                                    radius: Metrics.radiusSm
                                    color: Colors.surface
                                    border.width: 1
                                    border.color: pw.activeFocus ? Colors.accent : Colors.border
                                    TextInput {
                                        id: pw
                                        anchors.fill: parent
                                        anchors.leftMargin: Metrics.spaceSm
                                        anchors.rightMargin: Metrics.spaceSm
                                        verticalAlignment: TextInput.AlignVCenter
                                        echoMode: TextInput.Password
                                        color: Colors.textPrimary
                                        font.family: Typography.family
                                        font.pixelSize: Typography.sizeSm
                                        clip: true
                                        onVisibleChanged: if (visible) { text = ""; forceActiveFocus(); }
                                        Keys.onReturnPressed: connectBtn.connect()
                                        Keys.onEnterPressed: connectBtn.connect()
                                        Keys.onEscapePressed: wifiPage.pendingSsid = ""
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: pw.text.length === 0
                                            text: "Password"
                                            color: Colors.textMuted
                                            font: pw.font
                                        }
                                    }
                                }
                                IconButton {
                                    id: connectBtn
                                    icon: "check"
                                    active: true
                                    function connect() {
                                        if (pw.text.length === 0) return;
                                        NetworkService.connectTo(net.modelData.ssid, pw.text);
                                        pw.text = "";
                                        wifiPage.pendingSsid = "";
                                    }
                                    onClicked: connect()
                                }
                            }
                        }
                    }

                    Text {
                        // Reparented to the ListView itself: as a plain child it
                        // would sit in the (zero-height, clipped) contentItem.
                        parent: netList
                        anchors.centerIn: parent
                        visible: netList.count === 0
                        text: NetworkService.scanning ? "Scanning…" : "No networks found"
                        color: Colors.textMuted
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeSm
                    }
                }
            }

            // ════════════════════════ AUDIO ═══════════════════════════
            ColumnLayout {
                id: audioPage
                width: parent.width
                spacing: Metrics.spaceSm
                visible: opacity > 0
                opacity: panel.page === "audio" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                PageHeader { title: "Sound"; onBack: panel.page = "main" }

                SectionLabel { text: "Output" }
                Repeater {
                    model: AudioService.sinks
                    delegate: DeviceRow {
                        required property var modelData
                        label: AudioService.nodeLabel(modelData)
                        selected: AudioService.sink && AudioService.sink.id === modelData.id
                        icon: "volume-high"
                        onPicked: AudioService.setDefault(modelData)
                    }
                }
                Text {
                    visible: AudioService.sinks.length === 0
                    text: "No output devices"
                    color: Colors.textMuted
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeSm
                }

                SectionLabel { text: "Input"; Layout.topMargin: Metrics.spaceSm }
                Repeater {
                    model: AudioService.sources
                    delegate: DeviceRow {
                        required property var modelData
                        label: AudioService.nodeLabel(modelData)
                        selected: AudioService.source && AudioService.source.id === modelData.id
                        icon: "mic"
                        onPicked: AudioService.setDefault(modelData)
                    }
                }
                Text {
                    visible: AudioService.sources.length === 0
                    text: "No input devices"
                    color: Colors.textMuted
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeSm
                }
            }

            // ════════════════════════ DISPLAYS ════════════════════════
            ColumnLayout {
                id: displayPage
                width: parent.width
                spacing: Metrics.spaceSm
                visible: opacity > 0
                opacity: panel.page === "display" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                PageHeader { title: "Displays"; onBack: panel.page = "main" }

                Repeater {
                    model: DisplayService.monitors
                    delegate: Rectangle {
                        id: mon
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: monCol.implicitHeight + Metrics.spaceMd * 2
                        radius: Metrics.radiusMd
                        color: Colors.withAlpha(Colors.surface, Colors.dark ? 0.6 : 0.85)
                        ColumnLayout {
                            id: monCol
                            anchors.fill: parent
                            anchors.margins: Metrics.spaceMd
                            spacing: Metrics.spaceSm
                            RowLayout {
                                Layout.fillWidth: true
                                AetherIcon { width: 16; height: 16; name: "display"; color: mon.modelData.focused ? Colors.accent : Colors.textSecondary }
                                Text {
                                    text: mon.modelData.name
                                    color: Colors.textPrimary
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeSm
                                    font.weight: Typography.weightSemibold
                                }
                                Text {
                                    text: mon.modelData.width + "×" + mon.modelData.height + " @ " + Math.round(mon.modelData.refreshRate) + " Hz"
                                    color: Colors.textMuted
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeXs
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                            Text {
                                text: mon.modelData.description
                                visible: text.trim().length > 0
                                color: Colors.textMuted
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeXs
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Scale"; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeXs; Layout.fillWidth: true }
                                SegmentedControl {
                                    options: [{ value: "1", label: "100%" }, { value: "1.25", label: "125%" }, { value: "1.5", label: "150%" }, { value: "2", label: "200%" }]
                                    current: String(Number(mon.modelData.scale))
                                    onSelected: function(v) { DisplayService.setScale(mon.modelData, v); }
                                }
                            }
                        }
                    }
                }

                Text {
                    text: "Scale changes apply now and last until Hyprland reloads. Save layouts permanently in ~/.config/hypr/monitors.conf"
                        + (DisplayService.nwgDisplaysAvailable ? " or with Display Settings below." : ".")
                    color: Colors.textMuted
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeXs
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceSm
                    PillButton {
                        visible: DisplayService.nwgDisplaysAvailable
                        text: "Display Settings"
                        onClicked: { panel.hide(); DisplayService.openDisplaySettings(); }
                    }
                    PillButton {
                        text: "Wallpaper"
                        onClicked: { panel.hide(); EventBus.wallpaperPickerRequested(); }
                    }
                }
            }
        }
    }

    // ── Local building blocks ──────────────────────────────────────────
    component PageHeader: RowLayout {
        id: header
        property string title: ""
        signal back()
        Layout.fillWidth: true
        spacing: Metrics.spaceSm
        IconButton { icon: "chevron-left"; onClicked: header.back() }
        Text {
            text: header.title
            color: Colors.textPrimary
            font.family: Typography.family
            font.pixelSize: Typography.sizeLg
            font.weight: Typography.weightSemibold
            Layout.fillWidth: true
        }
    }

    component SliderRow: RowLayout {
        id: sr
        property string icon: ""
        property real value: 0
        property string valueText: ""
        property string trailingIcon: ""
        signal moved(real value)
        signal iconClicked()
        signal trailingClicked()
        Layout.fillWidth: true
        spacing: Metrics.spaceSm
        IconButton { icon: sr.icon; onClicked: sr.iconClicked() }
        Slider {
            Layout.fillWidth: true
            value: sr.value
            onMoved: function(v) { sr.moved(v); }
        }
        Text {
            text: sr.valueText
            color: Colors.textMuted
            font.family: Typography.family
            font.pixelSize: Typography.sizeXs
            Layout.preferredWidth: 40
            horizontalAlignment: Text.AlignRight
        }
        IconButton {
            visible: sr.trailingIcon.length > 0
            icon: sr.trailingIcon
            iconSize: 12
            implicitWidth: 26; implicitHeight: 26
            onClicked: sr.trailingClicked()
        }
    }

    component DeviceRow: Rectangle {
        id: dr
        property string label: ""
        property string icon: ""
        property bool selected: false
        signal picked()
        Layout.fillWidth: true
        implicitHeight: 40
        radius: Metrics.radiusMd
        color: selected ? Colors.accentSoft : (drArea.containsMouse ? Colors.surfaceHover : "transparent")
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Metrics.spaceMd
            anchors.rightMargin: Metrics.spaceMd
            AetherIcon { width: 15; height: 15; name: dr.icon; color: dr.selected ? Colors.accent : Colors.textSecondary }
            Text {
                text: dr.label
                color: Colors.textPrimary
                font.family: Typography.family
                font.pixelSize: Typography.sizeSm
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            AetherIcon { visible: dr.selected; width: 14; height: 14; name: "check"; color: Colors.accent }
        }
        MouseArea {
            id: drArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: dr.picked()
        }
    }

    component PillButton: Rectangle {
        id: pb
        property string text: ""
        signal clicked()
        implicitHeight: 32
        implicitWidth: pbLabel.implicitWidth + Metrics.spaceXl
        radius: Metrics.radiusPill
        color: pbArea.containsMouse ? Colors.accent : Colors.accentSoft
        Text {
            id: pbLabel
            anchors.centerIn: parent
            text: pb.text
            color: pbArea.containsMouse ? Colors.onAccent : Colors.accent
            font.family: Typography.family
            font.pixelSize: Typography.sizeXs
            font.weight: Typography.weightSemibold
        }
        MouseArea { id: pbArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
    }

    Connections {
        target: EventBus
        function onControlCenterRequested() { panel.toggle(); }
    }

    IpcHandler {
        target: "controlcenter"
        function toggle(): void { panel.toggle(); }
        function show(): void { panel.show(); }
        function hide(): void { panel.hide(); }
    }
}
