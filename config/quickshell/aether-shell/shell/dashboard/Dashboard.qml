import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// System dashboard (SUPER+N, or click the clock / stats in the bar).
//
// All numbers come from SystemMonitorService (the `aether telemetry`
// stream). Metrics the hardware doesn't expose are shown as "Unavailable"
// with the reason — never as a made-up 0. The per-process table is only
// sampled while this panel is open.
Scope {
    id: root

    PopupPanel {
        id: panel
        layerNamespace: "aether-dashboard"
        placement: "top"
        cardWidth: Math.min(820, (screen ? screen.width : 1280) - 48)
        cardHeight: Math.min(layout.implicitHeight + Metrics.spaceXl * 2, (screen ? screen.height : 900) - 100)

        onOpenChanged: {
            if (open) SystemMonitorService.wantProcessList(); else SystemMonitorService.releaseProcessList();
            if (open) HardwareService.ensureLoaded();
        }

        readonly property var gpu: SystemMonitorService.primaryGpu
        readonly property bool gpuActive: gpu !== null && gpu.state === "active"

        function gpuReason() {
            if (gpu === null) return "No GPU telemetry source detected";
            if (gpu.state === "suspended") return "Discrete GPU is asleep — not woken just to read it";
            return gpu.note || "This GPU/driver doesn't expose utilisation";
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: Metrics.spaceXl
            contentHeight: layout.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: layout
                width: parent.width
                spacing: Metrics.spaceLg

                // ── Header ─────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceMd
                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        Text {
                            text: "System"
                            color: Colors.textPrimary
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeXl
                            font.weight: Typography.weightBold
                        }
                        Text {
                            text: [
                                HardwareService.os,
                                SystemMonitorService.uptimeSeconds >= 0 ? "up " + SystemMonitorService.formatUptime(SystemMonitorService.uptimeSeconds) : "",
                                SystemMonitorService.loadAvg.length === 3 ? "load " + SystemMonitorService.loadAvg.map(function(x) { return x.toFixed(2); }).join(" ") : ""
                            ].filter(function(s) { return s.length > 0; }).join("  ·  ")
                            color: Colors.textMuted
                            font.family: Typography.family
                            font.pixelSize: Typography.sizeXs
                        }
                    }
                    Text {
                        visible: SystemMonitorService.source === "fallback"
                        text: "Basic mode — AetherOS backend unavailable"
                        color: Colors.warning
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeXs
                    }
                    IconButton { icon: "close"; onClicked: panel.hide() }
                }

                // ── Metric tiles ───────────────────────────────────────
                GridLayout {
                    Layout.fillWidth: true
                    columns: panel.cardWidth > 640 ? 3 : 2
                    rowSpacing: Metrics.spaceMd
                    columnSpacing: Metrics.spaceMd

                    StatTile {
                        Layout.fillWidth: true
                        icon: "cpu"
                        label: "CPU"
                        value: Math.round(SystemMonitorService.cpuUsage * 100) + "%"
                        ratio: SystemMonitorService.cpuUsage
                        detail: SystemMonitorService.cpuFreqMhz > 0 ? (SystemMonitorService.cpuFreqMhz / 1000).toFixed(2) + " GHz" : ""
                        history: SystemMonitorService.cpuHistory
                    }
                    StatTile {
                        Layout.fillWidth: true
                        icon: "memory"
                        label: "Memory"
                        value: SystemMonitorService.memUsedGb.toFixed(1) + " / " + SystemMonitorService.memTotalGb.toFixed(1) + " GB"
                        ratio: SystemMonitorService.memUsage
                        detail: SystemMonitorService.swapTotalGb > 0 ? "swap " + SystemMonitorService.swapUsedGb.toFixed(1) + " GB" : "no swap"
                        history: SystemMonitorService.memHistory
                    }
                    StatTile {
                        Layout.fillWidth: true
                        icon: "gpu"
                        label: panel.gpu ? "GPU · " + panel.gpu.name.replace(/\s*\[.*$/, "") : "GPU"
                        available: panel.gpuActive && panel.gpu.usage !== null
                        unavailableReason: panel.gpuReason()
                        value: available ? Math.round(panel.gpu.usage * 100) + "%" : ""
                        ratio: available ? panel.gpu.usage : -1
                        detail: available && panel.gpu.powerW !== null ? panel.gpu.powerW.toFixed(0) + " W" : ""
                        history: SystemMonitorService.gpuHistory
                    }
                    StatTile {
                        Layout.fillWidth: true
                        icon: "thermometer"
                        label: "Temperatures"
                        available: SystemMonitorService.cpuTemp >= 0 || (panel.gpuActive && panel.gpu.tempC !== null)
                        unavailableReason: SystemMonitorService.cpuTempNote || "No temperature sensors exposed"
                        value: (SystemMonitorService.cpuTemp >= 0 ? "CPU " + Math.round(SystemMonitorService.cpuTemp) + "°" : "CPU —")
                            + "   " + (panel.gpuActive && panel.gpu.tempC !== null ? "GPU " + Math.round(panel.gpu.tempC) + "°" : "GPU —")
                        ratio: -1
                        detail: "°C"
                    }
                    StatTile {
                        Layout.fillWidth: true
                        icon: "gpu"
                        label: "Video memory"
                        available: panel.gpuActive && panel.gpu.vramTotal !== null && panel.gpu.vramTotal > 0
                        unavailableReason: panel.gpu && panel.gpu.vendor === "intel"
                            ? "Integrated graphics share system RAM" : panel.gpuReason()
                        value: available ? SystemMonitorService.formatBytes(panel.gpu.vramUsed) + " / " + SystemMonitorService.formatBytes(panel.gpu.vramTotal) : ""
                        ratio: available ? panel.gpu.vramUsed / panel.gpu.vramTotal : -1
                    }
                    StatTile {
                        Layout.fillWidth: true
                        icon: "disk"
                        label: "Disk ( / )"
                        value: SystemMonitorService.diskUsedGb.toFixed(0) + " / " + SystemMonitorService.diskTotalGb.toFixed(0) + " GB"
                        ratio: SystemMonitorService.diskUsage
                        available: SystemMonitorService.diskTotalGb > 0
                    }
                    StatTile {
                        Layout.fillWidth: true
                        Layout.columnSpan: parent.columns === 3 ? 3 : 2
                        icon: "activity"
                        label: "Network" + (SystemMonitorService.netIface.length > 0 ? " · " + SystemMonitorService.netIface : "")
                        available: SystemMonitorService.netRxBps >= 0
                        unavailableReason: SystemMonitorService.source === "fallback" ? "Needs the AetherOS backend" : "Measuring…"
                        value: "↓ " + SystemMonitorService.formatRate(SystemMonitorService.netRxBps) + "     ↑ " + SystemMonitorService.formatRate(SystemMonitorService.netTxBps)
                        history: {
                            // Normalise to the window's peak so the graph uses its height.
                            const h = SystemMonitorService.netRxHistory;
                            const peak = Math.max.apply(null, h.concat([1]));
                            return h.map(function(v) { return v / peak; });
                        }
                        graphColor: Colors.info
                    }
                }

                // ── Per-thread load ────────────────────────────────────
                ColumnLayout {
                    visible: SystemMonitorService.cpuCores.length > 0
                    Layout.fillWidth: true
                    spacing: Metrics.spaceXs
                    SectionLabel { text: "CPU threads" }
                    Row {
                        Layout.fillWidth: true
                        spacing: 3
                        readonly property int n: SystemMonitorService.cpuCores.length
                        Repeater {
                            model: SystemMonitorService.cpuCores
                            delegate: Rectangle {
                                required property var modelData
                                width: Math.max(4, (layout.width - 3 * (parent.n - 1)) / Math.max(1, parent.n))
                                height: 26
                                radius: 3
                                color: Colors.withAlpha(Colors.textMuted, 0.15)
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: parent.height * Math.max(0.04, modelData)
                                    radius: 3
                                    color: Colors.load(modelData)
                                    Behavior on height { enabled: !Motion.reducedMotion; NumberAnimation { duration: Motion.slow } }
                                }
                            }
                        }
                    }
                }

                // ── Processes · system info · calendar ────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.spaceMd

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        implicitHeight: procCol.implicitHeight + Metrics.spaceMd * 2
                        radius: Metrics.radiusMd
                        color: Colors.withAlpha(Colors.surface, Colors.dark ? 0.55 : 0.75)

                        ColumnLayout {
                            id: procCol
                            anchors.fill: parent
                            anchors.margins: Metrics.spaceMd
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                SectionLabel { text: "Top processes"; Layout.fillWidth: true }
                                SectionLabel { text: "CPU"; Layout.preferredWidth: 52; horizontalAlignment: Text.AlignRight }
                                SectionLabel { text: "Memory"; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                            }
                            Repeater {
                                model: SystemMonitorService.processes
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Text {
                                        text: modelData.name
                                        color: Colors.textPrimary
                                        font.family: Typography.family
                                        font.pixelSize: Typography.sizeSm
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: (modelData.cpu * 100).toFixed(1) + "%"
                                        color: Colors.load(Math.min(1, modelData.cpu))
                                        font.family: Typography.familyMono
                                        font.pixelSize: Typography.sizeXs + 1
                                        Layout.preferredWidth: 52
                                        horizontalAlignment: Text.AlignRight
                                    }
                                    Text {
                                        text: SystemMonitorService.formatBytes(modelData.rss)
                                        color: Colors.textSecondary
                                        font.family: Typography.familyMono
                                        font.pixelSize: Typography.sizeXs + 1
                                        Layout.preferredWidth: 70
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }
                            Text {
                                visible: SystemMonitorService.processes.length === 0
                                text: SystemMonitorService.source === "fallback" ? "Process list needs the AetherOS backend" : "Sampling…"
                                color: Colors.textMuted
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeXs
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: 280
                        Layout.alignment: Qt.AlignTop
                        spacing: Metrics.spaceMd

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: infoCol.implicitHeight + Metrics.spaceMd * 2
                            radius: Metrics.radiusMd
                            color: Colors.withAlpha(Colors.surface, Colors.dark ? 0.55 : 0.75)
                            ColumnLayout {
                                id: infoCol
                                anchors.fill: parent
                                anchors.margins: Metrics.spaceMd
                                spacing: 3
                                SectionLabel { text: "Hardware" }
                                Text {
                                    text: HardwareService.loading ? "Detecting…"
                                        : !HardwareService.available ? "Hardware details need the AetherOS backend"
                                        : HardwareService.cpuModel
                                    color: Colors.textPrimary
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeXs + 1
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }
                                Text {
                                    visible: text.length > 0
                                    text: HardwareService.cpuTopology
                                    color: Colors.textMuted
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeXs
                                }
                                Repeater {
                                    model: HardwareService.gpus
                                    delegate: Text {
                                        required property var modelData
                                        text: modelData.vendorLabel + " " + modelData.name.replace(/\s*\[.*$/, "")
                                            + " · " + (modelData.driver || "no driver")
                                        color: Colors.textSecondary
                                        font.family: Typography.family
                                        font.pixelSize: Typography.sizeXs
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                                Text {
                                    visible: HardwareService.kernel.length > 0
                                    text: "Kernel " + HardwareService.kernel
                                    color: Colors.textMuted
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeXs
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: cal.implicitHeight + Metrics.spaceMd * 2
                            radius: Metrics.radiusMd
                            color: Colors.withAlpha(Colors.surface, Colors.dark ? 0.55 : 0.75)
                            CalendarWidget {
                                id: cal
                                anchors.fill: parent
                                anchors.margins: Metrics.spaceMd
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: EventBus
        function onDashboardRequested() { panel.toggle(); }
    }

    IpcHandler {
        target: "dashboard"
        function toggle(): void { panel.toggle(); }
        function show(): void { panel.show(); }
        function hide(): void { panel.hide(); }
    }
}
