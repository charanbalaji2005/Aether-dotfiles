import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../core"
import "../../services"
import "../../components"

// Application launcher (SUPER+D, or the grid button in the bar).
//
// Keyboard:  type to search · ↑/↓ select · PgUp/PgDn page · Home/End
//            Enter launch · Tab / Shift+Tab cycle categories
//            Ctrl+F (or right-click) pin/unpin favourite · Esc close
// With an empty query it shows Favourites, then Recent, then the chosen
// category (or all apps).
Scope {
    id: root

    PopupPanel {
        id: panel
        layerNamespace: "aether-launcher"
        placement: "center"
        cardWidth: Math.min(640, (screen ? screen.width : 1280) - 80)
        cardHeight: Math.min(560, (screen ? screen.height : 900) - 160)
        cardRadius: Metrics.radiusXl

        property string query: ""
        property string category: ""   // "" = all
        property int selectedIndex: 0
        readonly property var categoryList: [""].concat(ApplicationService.categories())

        // Rows: { kind: "header", label } or { kind: "app", app }
        readonly property var rows: {
            const out = [];
            if (query.length > 0) {
                for (const a of ApplicationService.search(query)) out.push({ kind: "app", app: a });
                return out;
            }
            const shown = {};
            if (category === "") {
                const favs = ApplicationService.favorites();
                if (favs.length > 0) {
                    out.push({ kind: "header", label: "Favourites" });
                    for (const a of favs) { out.push({ kind: "app", app: a }); shown[a.id] = true; }
                }
                const rec = ApplicationService.recents().filter(function(a) { return !shown[a.id]; });
                if (rec.length > 0) {
                    out.push({ kind: "header", label: "Recent" });
                    for (const a of rec) { out.push({ kind: "app", app: a }); shown[a.id] = true; }
                }
                out.push({ kind: "header", label: "All applications" });
                for (const a of ApplicationService.applications) if (!shown[a.id]) out.push({ kind: "app", app: a });
            } else {
                for (const a of ApplicationService.inCategory(category)) out.push({ kind: "app", app: a });
            }
            return out;
        }

        function _isApp(i) { return i >= 0 && i < rows.length && rows[i].kind === "app"; }
        function _firstApp() { for (let i = 0; i < rows.length; i++) if (_isApp(i)) return i; return -1; }

        // Move the selection by `delta` app rows, skipping section headers and
        // stopping at the ends.
        function move(delta) {
            if (rows.length === 0) return;
            const dir = delta > 0 ? 1 : -1;
            let remaining = Math.abs(delta);
            let i = _isApp(selectedIndex) ? selectedIndex : _firstApp();
            while (remaining > 0) {
                let j = i + dir;
                while (j >= 0 && j < rows.length && !_isApp(j)) j += dir;
                if (j < 0 || j >= rows.length) break;
                i = j;
                remaining--;
            }
            if (_isApp(i)) selectedIndex = i;
            list.positionViewAtIndex(selectedIndex, ListView.Contain);
        }

        function cycleCategory(dir) {
            const i = categoryList.indexOf(category);
            category = categoryList[(i + dir + categoryList.length) % categoryList.length];
        }

        function launchSelected() {
            if (!_isApp(selectedIndex)) return;
            ApplicationService.launch(rows[selectedIndex].app);
            hide();
        }

        // New search/category: start at the top. Other row changes (pinning a
        // favourite, config reload) keep the selection where it is.
        onQueryChanged: selectedIndex = _firstApp()
        onCategoryChanged: selectedIndex = _firstApp()
        onRowsChanged: if (!_isApp(selectedIndex)) selectedIndex = _firstApp()
        onOpened: {
            query = "";
            category = "";
            searchField.text = "";
            selectedIndex = _firstApp();
            searchField.forceActiveFocus();
            list.positionViewAtBeginning();
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Metrics.spaceLg
            spacing: Metrics.spaceMd

            // ── Search field ───────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                radius: Metrics.radiusLg
                color: Colors.withAlpha(Colors.surface, Colors.dark ? 0.75 : 0.95)
                border.width: 1
                border.color: searchField.activeFocus ? Colors.withAlpha(Colors.accent, 0.7) : Colors.border
                Behavior on border.color { enabled: !Motion.reducedMotion; ColorAnimation { duration: Motion.fast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Metrics.spaceMd
                    anchors.rightMargin: Metrics.spaceMd
                    spacing: Metrics.spaceSm

                    AetherIcon { width: 18; height: 18; name: "search"; color: Colors.textMuted }

                    TextInput {
                        id: searchField
                        Layout.fillWidth: true
                        color: Colors.textPrimary
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeLg
                        clip: true
                        selectionColor: Colors.accent
                        selectedTextColor: Colors.onAccent

                        onTextChanged: panel.query = text

                        Keys.onEscapePressed: panel.hide()
                        Keys.onDownPressed: panel.move(1)
                        Keys.onUpPressed: panel.move(-1)
                        Keys.onReturnPressed: panel.launchSelected()
                        Keys.onEnterPressed: panel.launchSelected()
                        Keys.onTabPressed: panel.cycleCategory(1)
                        Keys.onBacktabPressed: panel.cycleCategory(-1)
                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_PageDown) { panel.move(8); event.accepted = true; }
                            else if (event.key === Qt.Key_PageUp) { panel.move(-8); event.accepted = true; }
                            else if (event.key === Qt.Key_Home && searchField.text.length === 0) { panel.selectedIndex = panel._firstApp(); list.positionViewAtBeginning(); event.accepted = true; }
                            else if (event.key === Qt.Key_End && searchField.text.length === 0) { panel.move(panel.rows.length); event.accepted = true; }
                            else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                                if (panel._isApp(panel.selectedIndex)) ApplicationService.toggleFavorite(panel.rows[panel.selectedIndex].app);
                                event.accepted = true;
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search applications…"
                            color: Colors.textMuted
                            font: searchField.font
                            visible: searchField.text.length === 0
                        }
                    }

                    Text {
                        visible: panel.query.length > 0
                        text: panel.rows.length + " results"
                        color: Colors.textMuted
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeXs
                    }
                }
            }

            // ── Categories ─────────────────────────────────────────────
            Flickable {
                visible: Config.launcher.showCategories && panel.query.length === 0 && panel.categoryList.length > 1
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                contentWidth: chips.implicitWidth
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: chips
                    spacing: Metrics.spaceXs
                    Repeater {
                        model: panel.categoryList
                        delegate: Rectangle {
                            id: chip
                            required property string modelData
                            readonly property bool current: panel.category === modelData
                            height: 28
                            width: chipLabel.implicitWidth + Metrics.spaceLg
                            radius: Metrics.radiusPill
                            color: current ? Colors.accent : (chipArea.containsMouse ? Colors.surfaceHover : Colors.withAlpha(Colors.textMuted, 0.12))
                            Behavior on color { enabled: !Motion.reducedMotion; ColorAnimation { duration: Motion.fast } }
                            Text {
                                id: chipLabel
                                anchors.centerIn: parent
                                text: chip.modelData === "" ? "All" : ApplicationService.categoryLabels[chip.modelData]
                                color: chip.current ? Colors.onAccent : Colors.textSecondary
                                font.family: Typography.family
                                font.pixelSize: Typography.sizeXs
                                font.weight: Typography.weightMedium
                            }
                            MouseArea {
                                id: chipArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { panel.category = chip.modelData; searchField.forceActiveFocus(); }
                            }
                        }
                    }
                }
            }

            // ── Results ────────────────────────────────────────────────
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: panel.rows
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 400
                highlightMoveDuration: Motion.fast

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool isHeader: modelData.kind === "header"
                    readonly property bool selected: index === panel.selectedIndex
                    width: list.width
                    height: isHeader ? 30 : 50

                    SectionLabel {
                        visible: row.isHeader
                        anchors.left: parent.left
                        anchors.leftMargin: Metrics.spaceSm
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        text: row.isHeader ? row.modelData.label : ""
                    }

                    Rectangle {
                        visible: !row.isHeader
                        anchors.fill: parent
                        radius: Metrics.radiusMd
                        color: row.selected ? Colors.accentSoft : (rowArea.containsMouse ? Colors.withAlpha(Colors.textPrimary, 0.05) : "transparent")
                        border.width: row.selected ? 1 : 0
                        border.color: Colors.withAlpha(Colors.accent, 0.45)
                        Behavior on color { enabled: !Motion.reducedMotion; ColorAnimation { duration: Motion.fast } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Metrics.spaceSm
                            anchors.rightMargin: Metrics.spaceMd
                            spacing: Metrics.spaceMd

                            AppIcon {
                                iconName: row.isHeader ? "" : row.modelData.app.icon
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                scale: row.selected && !Motion.reducedMotion ? 1.08 : 1.0
                                Behavior on scale { enabled: !Motion.reducedMotion; NumberAnimation { duration: Motion.fast; easing.type: Motion.easeEmphasized } }
                            }

                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true
                                Text {
                                    text: row.isHeader ? "" : row.modelData.app.name
                                    color: Colors.textPrimary
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeMd
                                    font.weight: Typography.weightMedium
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: row.isHeader ? "" : (row.modelData.app.genericName || row.modelData.app.comment)
                                    visible: text.length > 0
                                    color: Colors.textMuted
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeXs
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            AetherIcon {
                                readonly property bool fav: !row.isHeader && ApplicationService.isFavorite(row.modelData.app)
                                visible: fav || rowArea.containsMouse || row.selected
                                width: 14; height: 14
                                name: fav ? "star-filled" : "star"
                                color: fav ? Colors.warning : Colors.textMuted
                            }
                        }

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onEntered: panel.selectedIndex = row.index
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton) ApplicationService.toggleFavorite(row.modelData.app);
                                else { panel.selectedIndex = row.index; panel.launchSelected(); }
                            }
                        }
                    }
                }

                Text {
                    parent: list
                    anchors.centerIn: parent
                    visible: panel.rows.filter(function(r) { return r.kind === "app"; }).length === 0
                    text: ApplicationService.available ? "No applications found" : "Loading applications…"
                    color: Colors.textMuted
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeSm
                }
            }

            // ── Hint bar ───────────────────────────────────────────────
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "↵ open   ·   Tab category   ·   Ctrl+F favourite   ·   Esc close"
                color: Colors.textMuted
                font.family: Typography.family
                font.pixelSize: Typography.sizeXs
            }
        }
    }

    Connections {
        target: EventBus
        function onLauncherRequested() { panel.toggle(); }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { panel.toggle(); }
        function show(): void { panel.show(); }
        function hide(): void { panel.hide(); }
    }
}
