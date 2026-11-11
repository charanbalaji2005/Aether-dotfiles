import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"
import "../../core"
import "../../services"
import "../../components"
import "../../animation"
import "../../graphics"

// The Dynamic Island: a glass pill at the top centre that shows what's
// happening right now and morphs open on hover or click.
//
// Content is derived from real providers only (IslandService): media
// (MPRIS), screen recording (aether-record), countdown / stopwatch / focus
// session (TimerService), charging (UPower), plus short-lived events
// (charger plugged, low battery, recording saved, timer done). When none
// of these exist the island is not shown at all.
//
// The surface is a fixed-size transparent layer whose input region is
// masked to the pill, so the empty area around it never swallows clicks.
// Size changes are springs on the pill, not window resizes.
Scope {
    id: root

    readonly property bool barTop: Config.bar.position !== "bottom"
    property bool expanded: false
    property int page: 0
    readonly property var pages: IslandService.activities
    readonly property string view: IslandService.hasEvent && !root.expanded ? "event"
        : pages.length > 0 ? pages[Math.min(root.page, pages.length - 1)] : ""
    readonly property bool shown: Config.island.enabled && (IslandService.hasEvent || pages.length > 0)
    onPagesChanged: if (root.page >= pages.length) root.page = 0

    // Target pill size per state.
    readonly property size collapsedSize: {
        switch (root.view) {
        case "event": return Qt.size(280, 36);
        case "media": return Qt.size(250, 36);
        case "recording": return Qt.size(150, 36);
        case "privacy": return Qt.size(150, 36);
        case "timer": case "stopwatch": return Qt.size(170, 36);
        case "charging": return Qt.size(130, 36);
        default: return Qt.size(120, 36);
        }
    }
    readonly property size expandedSize: root.view === "media" ? Qt.size(430, 156) : Qt.size(360, 112)
    readonly property size target: !root.shown ? Qt.size(36, 8) : root.expanded ? expandedSize : collapsedSize

    SpringValue { id: w; preset: "smooth"; target: root.target.width }
    SpringValue { id: h; preset: "smooth"; target: root.target.height }
    SpringValue { id: vis; preset: "smooth"; target: root.shown ? 1 : 0 }

    // The visualiser runs only while the media view is on screen.
    readonly property bool wantsVisualizer: root.shown && root.view === "media" && Config.island.visualizer
    property bool _vizHeld: false
    onWantsVisualizerChanged: {
        if (wantsVisualizer && !_vizHeld) { VisualizerService.want(); _vizHeld = true; }
        else if (!wantsVisualizer && _vizHeld) { VisualizerService.release(); _vizHeld = false; }
    }
    readonly property bool wantsPosition: root.shown && root.expanded && root.view === "media"
    property bool _posHeld: false
    onWantsPositionChanged: {
        if (wantsPosition && !_posHeld) { MediaService.wantPosition(); _posHeld = true; }
        else if (!wantsPosition && _posHeld) { MediaService.releasePosition(); _posHeld = false; }
    }

    Timer { id: hoverOpen; interval: 280; onTriggered: root.expanded = true }
    Timer { id: hoverClose; interval: 420; onTriggered: root.expanded = false }

    PanelWindow {
        id: win
        visible: vis.value > 0.01
        screen: ShellState.activeScreen ? ShellState.activeScreen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
        WlrLayershell.namespace: "aether-island"
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: ExclusionMode.Ignore
        anchors { top: root.barTop; bottom: !root.barTop }
        margins {
            top: root.barTop ? Config.bar.height + (Config.bar.style === "full" ? 0 : Metrics.barMargin) + Metrics.spaceXs : 0
            bottom: root.barTop ? 0 : Config.bar.height + Metrics.barMargin + Metrics.spaceXs
        }
        implicitWidth: 460
        implicitHeight: 172
        color: "transparent"
        mask: Region { item: pill }

        Item {
            id: pill
            width: Math.max(8, w.value)
            height: Math.max(4, h.value)
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.barTop ? 0 : parent.height - height
            opacity: vis.value
            scale: 0.9 + 0.1 * vis.value

            GlassPanel {
                id: glass
                anchors.fill: parent
                radius: Math.min(height / 2, 26)
                tintOpacity: Math.max(0.86, Colors.effectiveGlassOpacity)
                focused: root.expanded
                elevation: root.expanded ? 3 : 2
            }
            GlowEdge {
                anchors.fill: parent
                radius: glass.radius
                active: root.view === "recording" || (root.view === "media" && MediaService.playing && root.expanded)
                colorA: root.view === "recording" ? Colors.danger : Colors.accent
                colorB: root.view === "recording" ? Colors.warning : Colors.accentAlt
                intensity: root.expanded || root.view === "recording" ? 0.7 : 0.0
                visible: intensity > 0
            }

            HoverHandler {
                id: hover
                onHoveredChanged: {
                    if (hovered) { hoverClose.stop(); if (root.view !== "event") hoverOpen.restart(); }
                    else { hoverOpen.stop(); hoverClose.restart(); }
                }
            }
            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onTapped: function(point, button) {
                    if (root.view === "event") { IslandService.dismiss(); return; }
                    if (button === Qt.RightButton && root.pages.length > 1) { root.page = (root.page + 1) % root.pages.length; return; }
                    root.expanded = !root.expanded;
                }
            }
            WheelHandler {
                onWheel: function(event) {
                    if (root.pages.length > 1) root.page = (root.page + (event.angleDelta.y < 0 ? 1 : root.pages.length - 1)) % root.pages.length;
                }
            }

            // Content: one loader per view, cross-faded.
            Item {
                id: content
                anchors.fill: parent
                anchors.margins: root.expanded ? Metrics.spaceMd : Metrics.spaceSm
                clip: true

                Loader { anchors.fill: parent; active: root.view === "media"; sourceComponent: mediaView }
                Loader { anchors.fill: parent; active: root.view === "recording"; sourceComponent: recordingView }
                Loader { anchors.fill: parent; active: root.view === "timer" || root.view === "stopwatch"; sourceComponent: timerView }
                Loader { anchors.fill: parent; active: root.view === "charging"; sourceComponent: chargingView }
                Loader { anchors.fill: parent; active: root.view === "event"; sourceComponent: eventView }
                Loader { anchors.fill: parent; active: root.view === "privacy"; sourceComponent: privacyView }
            }

            // Page dots when several activities exist.
            Row {
                visible: root.expanded && root.pages.length > 1
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4
                Repeater {
                    model: root.pages.length
                    delegate: Rectangle {
                        required property int index
                        width: index === root.page ? 12 : 5; height: 5; radius: 2.5
                        color: index === root.page ? Colors.accent : Colors.withAlpha(Colors.textMuted, 0.5)
                        SpringBehavior on width { preset: "snappy" }
                    }
                }
            }
        }
    }

    // ── Views ──────────────────────────────────────────────────────────
    Component {
        id: mediaView
        Item {
            Visualizer {
                id: viz
                visible: !root.expanded
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 16
            }
            RowLayout {
                visible: !root.expanded
                anchors.fill: parent
                anchors.rightMargin: viz.visible ? 50 : 0
                spacing: Metrics.spaceSm
                Image {
                    Layout.preferredWidth: 22; Layout.preferredHeight: 22
                    source: MediaService.artUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(64, 64)
                    visible: status === Image.Ready
                }
                AetherIcon { visible: MediaService.artUrl.length === 0; width: 16; height: 16; name: "music"; color: Colors.accent }
                Text {
                    Layout.fillWidth: true
                    text: MediaService.title || MediaService.identity
                    color: Colors.textPrimary
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeSm
                    font.weight: Typography.weightMedium
                    elide: Text.ElideRight
                }
            }
            RowLayout {
                visible: root.expanded
                anchors.fill: parent
                spacing: Metrics.spaceMd
                Rectangle {
                    Layout.preferredWidth: 104; Layout.preferredHeight: 104
                    radius: Metrics.radiusMd
                    color: Colors.withAlpha(Colors.surface, 0.8)
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: MediaService.artUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize: Qt.size(256, 256)
                    }
                    AetherIcon { anchors.centerIn: parent; visible: MediaService.artUrl.length === 0; width: 34; height: 34; name: "music"; color: Colors.textMuted }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { Layout.fillWidth: true; text: MediaService.title || "Unknown track"; color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeLg; font.weight: Typography.weightSemibold; elide: Text.ElideRight }
                    Text { Layout.fillWidth: true; text: MediaService.artist || MediaService.identity; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; elide: Text.ElideRight }
                    Item { Layout.fillHeight: true }
                    Slider {
                        Layout.fillWidth: true
                        visible: MediaService.canSeek && MediaService.length > 0
                        from: 0; to: Math.max(1, MediaService.length)
                        value: MediaService.position
                        format: function(v) { return MediaService.formatTime(v); }
                        onMoved: function(v) { MediaService.seek(v); }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { visible: MediaService.length > 0; text: MediaService.formatTime(MediaService.position) + " / " + MediaService.formatTime(MediaService.length); color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs; font.features: { "tnum": 1 } }
                        Item { Layout.fillWidth: true }
                        IconButton { icon: "prev"; onClicked: MediaService.previous() }
                        IconButton { icon: MediaService.playing ? "pause" : "play"; active: true; onClicked: MediaService.playPause() }
                        IconButton { icon: "next"; onClicked: MediaService.next() }
                    }
                }
            }
        }
    }

    Component {
        id: recordingView
        RowLayout {
            spacing: Metrics.spaceSm
            Rectangle {
                width: 10; height: 10; radius: 5; color: Colors.danger
                SequentialAnimation on opacity {
                    running: Motion.animate && root.shown; loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 700 }
                    NumberAnimation { to: 1; duration: 700 }
                }
            }
            Text { text: TimerService.format(RecordingService.seconds); color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeMd; font.weight: Typography.weightSemibold; font.features: { "tnum": 1 } }
            Text { visible: root.expanded; Layout.fillWidth: true; text: "Recording the screen" + (RecordingService.withAudio ? " with system audio" : ""); color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; elide: Text.ElideRight }
            Item { Layout.fillWidth: !root.expanded }
            Rectangle {
                Layout.preferredWidth: stopLabel.implicitWidth + 18; Layout.preferredHeight: 24
                radius: 12; color: Colors.danger
                Text { id: stopLabel; anchors.centerIn: parent; text: "Stop"; color: "white"; font.family: Typography.family; font.pixelSize: Typography.sizeXs; font.weight: Typography.weightSemibold }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: RecordingService.stop() }
            }
        }
    }

    Component {
        id: timerView
        RowLayout {
            spacing: Metrics.spaceSm
            readonly property bool sw: root.view === "stopwatch"
            readonly property bool focus: !sw && TimerService.focusActive
            readonly property int left: sw ? Math.floor(TimerService.stopwatchMs / 1000) : (focus ? TimerService.focusLeft : TimerService.countdownLeft)
            readonly property int total: focus ? (TimerService.focusPhase === "focus" ? TimerService.focusMinutes : TimerService.breakMinutes) * 60 : TimerService.countdownTotal
            RadialGauge {
                Layout.preferredWidth: root.expanded ? 64 : 22; Layout.preferredHeight: Layout.preferredWidth
                visible: !parent.sw
                value: parent.total > 0 ? 1 - parent.left / parent.total : 0
                thickness: root.expanded ? 5 : 3; sweep: 360; valueText: ""; label: ""
                color: parent.focus && TimerService.focusPhase === "break" ? Colors.success : Colors.accent
            }
            AetherIcon { visible: parent.sw; width: 16; height: 16; name: "clock"; color: Colors.accent }
            ColumnLayout {
                spacing: 0
                Text { text: TimerService.format(parent.parent.left); color: Colors.textPrimary; font.family: Typography.familyDisplay; font.pixelSize: root.expanded ? Typography.sizeXxl : Typography.sizeMd; font.weight: Typography.weightSemibold; font.features: { "tnum": 1 } }
                Text {
                    visible: root.expanded
                    text: parent.parent.sw ? "Stopwatch" : parent.parent.focus ? (TimerService.focusPhase === "focus" ? "Focus · round " + TimerService.focusRound : "Break") : (TimerService.countdownPaused ? "Paused" : "Timer")
                    color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm
                }
            }
            Item { Layout.fillWidth: true }
            IconButton {
                visible: root.expanded
                icon: parent.sw ? (TimerService.stopwatchRunning ? "pause" : "play") : (TimerService.countdownPaused ? "play" : "pause")
                onClicked: {
                    if (parent.sw) { if (TimerService.stopwatchRunning) TimerService.pauseStopwatch(); else TimerService.startStopwatch(); }
                    else if (TimerService.countdownPaused) TimerService.resumeCountdown(); else TimerService.pauseCountdown();
                }
                enabledState: parent.sw || !parent.focus
            }
            IconButton {
                visible: root.expanded
                icon: "close"
                onClicked: { if (parent.sw) TimerService.resetStopwatch(); else if (parent.focus) TimerService.stopFocus(); else TimerService.cancelCountdown(); }
            }
        }
    }

    Component {
        id: chargingView
        RowLayout {
            spacing: Metrics.spaceSm
            BatteryIcon { style: Config.battery.style === "percent" ? "classic" : Config.battery.style; level: PowerService.percentage / 100; charging: true }
            Text { text: Math.round(PowerService.percentage) + "%"; color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeMd; font.weight: Typography.weightSemibold }
            Text { visible: root.expanded; Layout.fillWidth: true; text: PowerService.formattedTimeRemaining() ? PowerService.formattedTimeRemaining() + " until full" : "Charging"; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; elide: Text.ElideRight }
        }
    }

    Component {
        id: eventView
        RowLayout {
            readonly property var ev: IslandService.current ? IslandService.current : { kind: "", payload: {} }
            spacing: Metrics.spaceSm
            AetherIcon {
                width: 16; height: 16
                name: ({ battery: parent.ev.payload.charging ? "bolt" : "power", recording: "display", timer: "clock",
                         network: parent.ev.payload.vpn ? "lock" : "wifi", screenshot: "image", clipboard: "clipboard",
                         external: "activity", info: "gauge" })[parent.ev.kind] || "bell"
                color: parent.ev.kind === "battery" && !parent.ev.payload.charging && parent.ev.payload.level <= Config.battery.lowThreshold ? Colors.warning : Colors.accent
            }
            Text {
                Layout.fillWidth: true
                text: (parent.ev.payload.text || "") + (parent.ev.kind === "battery" && parent.ev.payload.level !== undefined ? " · " + Math.round(parent.ev.payload.level) + "%" : "")
                      + (parent.ev.payload.body ? " — " + parent.ev.payload.body : "")
                color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; font.weight: Typography.weightMedium
                elide: Text.ElideRight
            }
        }
    }

    Component {
        id: privacyView
        RowLayout {
            spacing: Metrics.spaceSm
            Rectangle { visible: PrivacyService.micInUse; width: 10; height: 10; radius: 5; color: Colors.warning }
            Rectangle { visible: PrivacyService.cameraInUse; width: 10; height: 10; radius: 5; color: Colors.success }
            Text {
                text: PrivacyService.micInUse && PrivacyService.cameraInUse ? "Mic + camera" : PrivacyService.cameraInUse ? "Camera" : "Microphone"
                color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; font.weight: Typography.weightMedium
            }
            Text {
                visible: root.expanded
                Layout.fillWidth: true
                text: "in use by " + PrivacyService.micUsers.concat(PrivacyService.cameraUsers).filter(function(v, i, a) { return a.indexOf(v) === i; }).join(", ")
                color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; elide: Text.ElideRight
            }
        }
    }

    component Visualizer: Row {
        spacing: 2
        readonly property var bars: VisualizerService.bars
        Repeater {
            model: 8
            delegate: Rectangle {
                required property int index
                readonly property real v: parent.bars.length ? parent.bars[Math.floor(index * parent.bars.length / 8)] : (MediaService.playing ? 0.25 : 0.1)
                anchors.verticalCenter: parent.verticalCenter
                width: 3; radius: 1.5
                height: Math.max(3, parent.height * v)
                color: Colors.accent
                Behavior on height { enabled: Motion.animate; NumberAnimation { duration: 90 } }
            }
        }
    }

    IpcHandler {
        target: "island"
        function toggle(): void { root.expanded = !root.expanded; }
        function next(): void { if (root.pages.length > 1) root.page = (root.page + 1) % root.pages.length; }
        function post(title: string, body: string): bool { return IslandService.post(title, body); }
    }
}
