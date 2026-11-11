import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../core"
import "../../services"
import "../../components"
import "../../animation"
import "../../graphics"

// System Centre (SUPER+X): hardware, processes, services, updates,
// security, snapshots and the performance report.
//
// Everything is loaded when its tab opens — nothing here polls in the
// background. It observes far more than it changes; the actions it does
// offer are bounded:
//   * processes: SIGTERM, then (armed second click) SIGKILL — your own
//     processes only (the kernel enforces that; no privilege is used)
//   * services: start/stop/restart *user* units
//   * updates: listed here; installing opens a terminal running
//     `sudo dnf upgrade --refresh` so you see and approve the transaction
//   * snapshots: create / mark good / restore (restore snapshots first)
// Security settings are shown, never changed.
Scope {
    id: root

    readonly property var tabs: [
        { id: "overview", label: "Hardware", icon: "cpu" },
        { id: "processes", label: "Processes", icon: "activity" },
        { id: "services", label: "Services", icon: "gear" },
        { id: "updates", label: "Updates", icon: "arrow-down" },
        { id: "security", label: "Security", icon: "lock" },
        { id: "snapshots", label: "Snapshots", icon: "refresh" },
        { id: "performance", label: "Performance", icon: "gauge" }
    ]

    PopupPanel {
        id: panel
        layerNamespace: "aether-systemcenter"
        placement: "center"
        cardWidth: Math.min(900, (screen ? screen.width : 1280) - 80)
        cardHeight: Math.min(620, (screen ? screen.height : 900) - 120)
        cardRadius: Metrics.radiusXl

        property string tab: "overview"
        property string filter: ""
        property string armedPid: ""
        property bool _procHeld: false

        function load(t) {
            switch (t) {
            case "overview": HardwareService.ensureLoaded(); break;
            case "services": SystemService.loadServices(); break;
            case "updates": if (!SystemService.updates) SystemService.loadUpdates(); break;
            case "security": SystemService.loadSecurity(); break;
            case "snapshots": SystemService.loadSnapshots(); break;
            }
        }
        readonly property bool wantsProcs: open && tab === "processes"
        onWantsProcsChanged: {
            if (wantsProcs && !_procHeld) { SystemMonitorService.wantProcessList(); _procHeld = true; }
            else if (!wantsProcs && _procHeld) { SystemMonitorService.releaseProcessList(); _procHeld = false; }
        }
        onOpened: load(tab)
        onTabChanged: { armedPid = ""; if (open) load(tab); }

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
                    text: "System"
                    color: Colors.textPrimary
                    font.family: Typography.family; font.pixelSize: Typography.sizeXl; font.weight: Typography.weightBold
                    Layout.leftMargin: Metrics.spaceSm; Layout.bottomMargin: Metrics.spaceSm
                }
                Repeater {
                    model: root.tabs
                    delegate: NavItem {
                        required property var modelData
                        label: modelData.label; icon: modelData.icon
                        current: panel.tab === modelData.id
                        badge: modelData.id === "updates" && SystemService.updates && SystemService.updates.count > 0 ? String(SystemService.updates.count)
                             : modelData.id === "services" && SystemService.services && SystemService.services.failed && SystemService.services.failed.length > 0 ? "!" : ""
                        onClicked: panel.tab = modelData.id
                    }
                }
                Item { Layout.fillHeight: true }
                Text {
                    Layout.fillWidth: true; Layout.margins: Metrics.spaceSm
                    visible: SystemService.error.length > 0
                    text: SystemService.error
                    color: Colors.danger; wrapMode: Text.WordWrap
                    font.family: Typography.family; font.pixelSize: Typography.sizeXs
                }
            }

            Rectangle { Layout.preferredWidth: Metrics.borderWidth; Layout.fillHeight: true; color: Colors.border }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: Metrics.spaceXl
                sourceComponent: ({ overview: hwTab, processes: procTab, services: svcTab, updates: updTab,
                                    security: secTab, snapshots: snapTab, performance: perfTab })[panel.tab]
            }
        }
    }

    // ── Tabs ───────────────────────────────────────────────────────────
    Component {
        id: hwTab
        Flickable {
            contentHeight: hwCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: hwCol
                width: parent.width
                spacing: Metrics.spaceLg
                Heading { text: "Hardware" }
                RowLayout {
                    spacing: Metrics.spaceLg
                    RadialGauge { label: "CPU"; value: SystemMonitorService.cpuUsage
                                  detail: SystemMonitorService.cpuTemp >= 0 ? Math.round(SystemMonitorService.cpuTemp) + " °C" : "" }
                    RadialGauge { label: "Memory"; value: SystemMonitorService.memUsage
                                  detail: SystemMonitorService.memUsedGb.toFixed(1) + " / " + SystemMonitorService.memTotalGb.toFixed(1) + " GB" }
                    RadialGauge {
                        readonly property var g: SystemMonitorService.primaryGpu
                        label: "GPU"
                        available: g !== null && g !== undefined && g.usage !== null && g.usage !== undefined
                        value: available ? g.usage : 0
                        detail: g && g.tempC !== null && g.tempC !== undefined ? Math.round(g.tempC) + " °C" : (g && g.note ? g.note : "")
                    }
                    RadialGauge { label: "Disk /"; value: SystemMonitorService.diskUsage
                                  detail: SystemMonitorService.diskUsedGb.toFixed(0) + " / " + SystemMonitorService.diskTotalGb.toFixed(0) + " GB" }
                }
                InfoRow { label: "Operating system"; value: HardwareService.os || "—" }
                InfoRow { label: "Kernel"; value: HardwareService.kernel || "—" }
                InfoRow { label: "Processor"; value: (HardwareService.cpuModel || "—") + (HardwareService.cpuTopology ? "  ·  " + HardwareService.cpuTopology : "") }
                Repeater {
                    model: HardwareService.gpus
                    delegate: InfoRow {
                        required property var modelData
                        label: "Graphics (" + (modelData.kind || "gpu") + ")"
                        value: (modelData.name || "?") + "  ·  driver " + (modelData.driver || "none")
                    }
                }
                InfoRow { label: "GPU layout"; value: HardwareService.gpuLayout || "—" }
                InfoRow { label: "Uptime"; value: SystemMonitorService.formatUptime(SystemMonitorService.uptimeSeconds) }
                InfoRow {
                    visible: PowerService.available
                    label: "Battery"
                    value: Math.round(PowerService.percentage) + "%" + (PowerService.health >= 0 ? "  ·  health " + Math.round(PowerService.health) + "%" : "")
                           + (PowerService.energyRate > 0 ? "  ·  " + PowerService.energyRate.toFixed(1) + " W" : "")
                }
                Text {
                    visible: !HardwareService.available
                    text: "The AetherOS backend (aether hardware) isn't available, so static hardware facts can't be shown."
                    color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }
        }
    }

    Component {
        id: procTab
        ColumnLayout {
            spacing: Metrics.spaceMd
            RowLayout {
                Heading { text: "Processes" }
                Item { Layout.fillWidth: true }
                SearchField { Layout.preferredWidth: 240; placeholder: "Filter by name or PID"; onEdited: function(t) { panel.filter = t; } }
            }
            Text {
                visible: SystemMonitorService.source !== "telemetry"
                text: "The process list needs the AetherOS telemetry backend (python3)."
                color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm
            }
            RowLayout {
                Layout.fillWidth: true
                Text { Layout.preferredWidth: 70; text: "PID"; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
                Text { Layout.fillWidth: true; text: "Name"; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
                Text { Layout.preferredWidth: 70; text: "CPU"; horizontalAlignment: Text.AlignRight; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
                Text { Layout.preferredWidth: 90; text: "Memory"; horizontalAlignment: Text.AlignRight; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
                Item { Layout.preferredWidth: 96 }
            }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true; spacing: 2
                model: SystemMonitorService.processes.filter(function(p) {
                    const f = panel.filter.toLowerCase();
                    return f.length === 0 || String(p.pid).indexOf(f) === 0 || (p.name || "").toLowerCase().indexOf(f) >= 0;
                })
                delegate: Rectangle {
                    id: prow
                    required property var modelData
                    width: ListView.view.width; height: 32
                    radius: Metrics.radiusSm
                    color: pa.containsMouse ? Colors.surfaceHover : "transparent"
                    readonly property bool armed: panel.armedPid === String(modelData.pid)
                    MouseArea { id: pa; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: Metrics.spaceSm; anchors.rightMargin: Metrics.spaceSm
                        Text { Layout.preferredWidth: 70; text: prow.modelData.pid; color: Colors.textMuted; font.family: Typography.familyMono; font.pixelSize: Typography.sizeSm }
                        Text { Layout.fillWidth: true; text: prow.modelData.name; color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; elide: Text.ElideRight }
                        Text { Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; text: (prow.modelData.cpu * 100).toFixed(1) + "%"; color: Colors.load(prow.modelData.cpu); font.family: Typography.family; font.pixelSize: Typography.sizeSm; font.features: { "tnum": 1 } }
                        Text { Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight; text: SystemMonitorService.formatBytes(prow.modelData.rss); color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; font.features: { "tnum": 1 } }
                        Pill {
                            Layout.preferredWidth: 96
                            text: prow.armed ? "Force kill?" : "End"
                            danger: prow.armed
                            visible: pa.containsMouse || prow.armed
                            onClicked: {
                                // First click: SIGTERM (lets it clean up). If it's still
                                // listed, the button arms SIGKILL for the next click.
                                if (prow.armed) { SystemService.terminate(prow.modelData.pid, true); panel.armedPid = ""; }
                                else { SystemService.terminate(prow.modelData.pid, false); panel.armedPid = String(prow.modelData.pid); }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: svcTab
        ColumnLayout {
            spacing: Metrics.spaceMd
            RowLayout {
                Heading { text: "User services" }
                Item { Layout.fillWidth: true }
                Pill { text: "Refresh"; onClicked: SystemService.loadServices() }
            }
            Text {
                visible: SystemService.services && SystemService.services.available === false
                text: SystemService.services ? (SystemService.services.reason || "") : ""
                color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm
            }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.preferredHeight: 260
                clip: true; spacing: 2
                model: SystemService.services && SystemService.services.units
                    ? SystemService.services.units.filter(function(u) { return u.aether || u.active === "active" || u.active === "failed"; }) : []
                delegate: Rectangle {
                    id: srow
                    required property var modelData
                    width: ListView.view.width; height: 34
                    radius: Metrics.radiusSm
                    color: sa.containsMouse ? Colors.surfaceHover : "transparent"
                    MouseArea { id: sa; anchors.fill: parent; hoverEnabled: true; onClicked: SystemService.loadLog(srow.modelData.unit) }
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: Metrics.spaceSm; anchors.rightMargin: Metrics.spaceSm
                        Rectangle { width: 8; height: 8; radius: 4; color: srow.modelData.active === "failed" ? Colors.danger : srow.modelData.active === "active" ? Colors.success : Colors.textMuted }
                        Text { Layout.preferredWidth: 260; text: srow.modelData.unit; color: srow.modelData.aether ? Colors.accent : Colors.textPrimary; font.family: Typography.familyMono; font.pixelSize: Typography.sizeSm; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: srow.modelData.description; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs; elide: Text.ElideRight }
                        Pill { visible: sa.containsMouse; text: srow.modelData.active === "active" ? "Restart" : "Start"; onClicked: SystemService.serviceAction(srow.modelData.active === "active" ? "restart" : "start", srow.modelData.unit) }
                        Pill { visible: sa.containsMouse && srow.modelData.active === "active"; text: "Stop"; onClicked: SystemService.serviceAction("stop", srow.modelData.unit) }
                    }
                }
            }
            LogBox {
                Layout.fillWidth: true; Layout.preferredHeight: 150
                visible: SystemService.serviceLog.unit.length > 0
                title: "journalctl --user -u " + SystemService.serviceLog.unit
                text: SystemService.serviceLog.text
            }
        }
    }

    Component {
        id: updTab
        ColumnLayout {
            spacing: Metrics.spaceMd
            readonly property var u: SystemService.updates
            RowLayout {
                Heading { text: "Fedora updates" }
                Item { Layout.fillWidth: true }
                Spinner { visible: CliService.isBusy("updates"); width: 16; height: 16 }
                Pill { text: "Check again"; onClicked: SystemService.loadUpdates() }
                Pill { visible: parent.parent.u && parent.parent.u.count > 0; text: "Install in terminal…"; accent: true; onClicked: SystemService.runUpgrade() }
            }
            Text {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: !parent.u ? "Checking… (dnf check-update can take a minute on slow mirrors)"
                    : parent.u.available === false ? parent.u.reason
                    : parent.u.count === 0 ? "Everything is up to date."
                    : parent.u.count + " update(s) available" + (parent.u.rebootRequired === true ? " · a reboot is pending from an earlier update" : "")
                      + (parent.u.corePackages && parent.u.corePackages.length ? " · includes " + parent.u.corePackages.slice(0, 4).join(", ") : "")
                color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeMd
            }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                model: parent.u && parent.u.packages ? parent.u.packages : []
                delegate: RowLayout {
                    required property var modelData
                    width: ListView.view.width; height: 24
                    Text { Layout.fillWidth: true; text: modelData.name; color: Colors.textPrimary; font.family: Typography.familyMono; font.pixelSize: Typography.sizeSm; elide: Text.ElideRight }
                    Text { Layout.preferredWidth: 260; text: modelData.version; color: Colors.textSecondary; font.family: Typography.familyMono; font.pixelSize: Typography.sizeSm; elide: Text.ElideRight }
                    Text { Layout.preferredWidth: 110; text: modelData.repo; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
                }
            }
        }
    }

    Component {
        id: secTab
        ColumnLayout {
            spacing: Metrics.spaceMd
            Heading { text: "Security & privacy" }
            Text {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: "Read-only. AetherOS never changes SELinux, the firewall or Secure Boot; where something is off, the fix is shown for you to run."
                color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm
            }
            Repeater {
                model: SystemService.security ? SystemService.security.items : []
                delegate: MotionCard {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: secRow.implicitHeight + Metrics.spaceMd * 2
                    interactive: false
                    index: index
                    RowLayout {
                        id: secRow
                        anchors.fill: parent; anchors.margins: Metrics.spaceMd
                        spacing: Metrics.spaceMd
                        Rectangle { width: 10; height: 10; radius: 5; color: modelData.level === "pass" ? Colors.success : modelData.level === "warn" ? Colors.warning : Colors.info }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 1
                            Text { text: modelData.label + "  ·  " + modelData.value; color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeMd; font.weight: Typography.weightMedium }
                            Text { visible: modelData.detail.length > 0; Layout.fillWidth: true; text: modelData.detail; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs; wrapMode: Text.WordWrap }
                        }
                    }
                }
            }
            InfoRow { label: "Screen lock after"; value: Config.lock.idleLockMinutes > 0 ? Config.lock.idleLockMinutes + " min idle" : "never (Settings → Lock screen)" }
            InfoRow { label: "Notification contents when locked"; value: Config.lock.hideNotificationContent ? "hidden" : "shown" }
            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: snapTab
        ColumnLayout {
            id: snapCol
            spacing: Metrics.spaceMd
            property string armed: ""
            RowLayout {
                Heading { text: "Configuration snapshots" }
                Item { Layout.fillWidth: true }
                Pill { text: "Mark current as known-good"; onClicked: SystemService.markGood() }
                Pill { text: "Create snapshot"; accent: true; onClicked: SystemService.createSnapshot() }
            }
            Text {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: "Snapshots hold your AetherOS settings, generated Hyprland fragments, terminal themes, layouts and profiles. Restoring takes a snapshot of the current state first, so it can be undone."
                color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm
            }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true; spacing: 4
                model: SystemService.snapshots
                delegate: Rectangle {
                    id: snrow
                    required property var modelData
                    width: ListView.view.width; height: 40
                    radius: Metrics.radiusSm
                    color: na.containsMouse ? Colors.surfaceHover : Colors.withAlpha(Colors.surface, 0.5)
                    MouseArea { id: na; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: Metrics.spaceMd; anchors.rightMargin: Metrics.spaceSm
                        Text { Layout.fillWidth: true; text: snrow.modelData.name + (snrow.modelData.lastKnownGood ? "   ★ known-good" : ""); color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; elide: Text.ElideRight }
                        Text { text: snrow.modelData.files + " file(s)"; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
                        Text { visible: !snrow.modelData.valid; text: "damaged"; color: Colors.danger; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
                        Pill {
                            readonly property bool isArmed: snapCol.armed === snrow.modelData.name
                            visible: snrow.modelData.valid && (na.containsMouse || isArmed)
                            text: isArmed ? "Click to restore" : "Restore"
                            danger: isArmed
                            onClicked: {
                                if (isArmed) { SystemService.restoreSnapshot(snrow.modelData.name); snapCol.armed = ""; }
                                else snapCol.armed = snrow.modelData.name;
                            }
                        }
                    }
                }
            }
            Text {
                visible: SystemService.snapshots.length === 0
                text: "No snapshots yet."
                color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm
            }
        }
    }

    Component {
        id: perfTab
        Flickable {
            contentHeight: perfCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: perfCol
                width: parent.width
                spacing: Metrics.spaceMd
                Heading { text: "Performance report" }
                InfoRow { label: "Visual quality now"; value: PerformanceService.tier + (Config.effects.quality === "auto" ? " (automatic)" : " (manual)") }
                InfoRow { label: "Hardware recommendation"; value: PerformanceService.hardwareTier }
                InfoRow { label: "Shader effects"; value: PerformanceService.shaders ? "on" : "off" + (Object.keys(ShaderLibrary.failedNames()).length ? " (failed: " + Object.keys(ShaderLibrary.failedNames()).join(", ") + ")" : "") }
                InfoRow { label: "Particles · parallax · glow"; value: [PerformanceService.particles ? "particles" : "", PerformanceService.parallax ? "parallax" : "", PerformanceService.glow ? "glow" : ""].filter(function(x) { return x; }).join(" · ") || "none" }
                InfoRow { label: "Video wallpaper"; value: VideoWallpaperService.state }
                InfoRow { label: "Animation frame time"; value: AnimationCoordinator.averageFrameMs > 0 ? AnimationCoordinator.averageFrameMs.toFixed(1) + " ms average · budget " + AnimationCoordinator.budgetMs.toFixed(1) + " ms · late " + AnimationCoordinator.lateFrames + "/" + AnimationCoordinator.windowSize : "not measured yet (measured only while the shell animates)" }
                InfoRow { label: "Telemetry"; value: SystemMonitorService.source + " · every " + (SystemMonitorService.effectiveIntervalSeconds).toFixed(1) + " s" }
                SectionLabel { text: "Why"; Layout.topMargin: Metrics.spaceSm }
                Repeater {
                    model: PerformanceService.reasons
                    delegate: Text { required property string modelData; Layout.fillWidth: true; text: "• " + modelData; wrapMode: Text.WordWrap; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
                }
                SectionLabel { text: "Automatic changes this session"; Layout.topMargin: Metrics.spaceSm }
                Text { visible: PerformanceService.history.length === 0; text: "None."; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
                Repeater {
                    model: PerformanceService.history
                    delegate: Text { required property var modelData; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: modelData.time + "  " + modelData.from + " → " + modelData.to + " — " + modelData.why; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
                }
                SectionLabel { text: "Automation log"; Layout.topMargin: Metrics.spaceSm }
                Text { visible: AutomationService.history.length === 0; text: Config.automation.enabled ? "No rule has run yet." : "Automation is off."; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
                Repeater {
                    model: AutomationService.history.slice(0, 15)
                    delegate: Text { required property var modelData; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: modelData.time + "  " + (modelData.ok ? "✓ " : "✗ ") + modelData.name + (modelData.detail ? " — " + modelData.detail : ""); color: modelData.ok ? Colors.textSecondary : Colors.danger; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
                }
            }
        }
    }

    // ── Pieces ─────────────────────────────────────────────────────────
    component Heading: Text {
        color: Colors.textPrimary
        font.family: Typography.family; font.pixelSize: Typography.sizeXl; font.weight: Typography.weightSemibold
    }
    component InfoRow: RowLayout {
        property string label
        property string value
        Layout.fillWidth: true
        spacing: Metrics.spaceMd
        Text { Layout.preferredWidth: 210; text: parent.label; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
        Text { Layout.fillWidth: true; text: parent.value; color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; wrapMode: Text.WordWrap }
    }
    component NavItem: Rectangle {
        id: nav
        property string label
        property string icon
        property string badge: ""
        property bool current: false
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 36
        radius: Metrics.radiusMd
        color: current ? Colors.accentSoft : (nma.containsMouse ? Colors.surfaceHover : "transparent")
        Behavior on color { enabled: Motion.animate; ColorAnimation { duration: Motion.fast } }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: Metrics.spaceMd; anchors.rightMargin: Metrics.spaceSm
            spacing: Metrics.spaceSm
            AetherIcon { width: 15; height: 15; name: nav.icon; color: nav.current ? Colors.accent : Colors.textSecondary }
            Text { Layout.fillWidth: true; text: nav.label; color: nav.current ? Colors.accent : Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; font.weight: Typography.weightMedium }
            Rectangle {
                visible: nav.badge.length > 0
                width: Math.max(18, bt.implicitWidth + 8); height: 18; radius: 9
                color: nav.badge === "!" ? Colors.danger : Colors.accent
                Text { id: bt; anchors.centerIn: parent; text: nav.badge; color: Colors.onAccent; font.family: Typography.family; font.pixelSize: Typography.sizeXs; font.weight: Typography.weightBold }
            }
        }
        MouseArea { id: nma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: nav.clicked() }
        Accessible.role: Accessible.PageTab
        Accessible.name: nav.label
    }
    component Pill: Rectangle {
        id: pill
        property string text
        property bool accent: false
        property bool danger: false
        signal clicked()
        implicitWidth: pt.implicitWidth + 22
        implicitHeight: 28
        radius: 14
        color: danger ? Colors.danger : accent ? Colors.accent : (pma.containsMouse ? Colors.surfaceActive : Colors.surfaceHover)
        Text { id: pt; anchors.centerIn: parent; text: pill.text; color: pill.danger || pill.accent ? Colors.onAccent : Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeXs; font.weight: Typography.weightSemibold }
        MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pill.clicked() }
        Accessible.role: Accessible.Button
        Accessible.name: pill.text
    }
    component SearchField: Rectangle {
        id: sf
        property string placeholder
        signal edited(string text)
        implicitHeight: 32
        radius: 16
        color: Colors.withAlpha(Colors.surface, 0.9)
        border.width: 1; border.color: input.activeFocus ? Colors.accent : Colors.border
        TextInput {
            id: input
            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
            verticalAlignment: TextInput.AlignVCenter
            color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm
            onTextChanged: sf.edited(text)
        }
        Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; visible: input.text.length === 0; text: sf.placeholder; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
    }
    component LogBox: Rectangle {
        property string title
        property string text
        radius: Metrics.radiusMd
        color: Colors.withAlpha(Colors.bg0, 0.7)
        border.width: 1; border.color: Colors.border
        ColumnLayout {
            anchors.fill: parent; anchors.margins: Metrics.spaceSm
            Text { text: parent.parent.title; color: Colors.textMuted; font.family: Typography.familyMono; font.pixelSize: Typography.sizeXs }
            Flickable {
                Layout.fillWidth: true; Layout.fillHeight: true
                contentHeight: logText.implicitHeight; clip: true
                Text { id: logText; width: parent.width; text: parent.parent.parent.text; color: Colors.textSecondary; font.family: Typography.familyMono; font.pixelSize: Typography.sizeXs; wrapMode: Text.WrapAnywhere }
            }
        }
    }

    Connections {
        target: EventBus
        function onSystemCenterRequested(tab) {
            if (tab && tab.length) panel.tab = tab;
            panel.toggle();
        }
    }
    IpcHandler {
        target: "systemcenter"
        function toggle(): void { panel.toggle(); }
        function show(): void { panel.show(); }
    }
}
