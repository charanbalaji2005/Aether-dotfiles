import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme"
import "../../core"
import "../../services"
import "../../components"
import "../settings/SettingsIndex.js" as SettingsIndex

// Application launcher (SUPER+D, or the grid button in the bar).
//
// Keyboard:  type to search · ↑/↓ select · PgUp/PgDn page · Home/End
//            Enter launch · Tab / Shift+Tab cycle categories
//            Ctrl+F (or right-click) pin/unpin favourite · Esc close
// Prefixes: "/" searches your files, ">" runs a command in your terminal
// (only when you press Enter). Plain searches also match Settings and
// AetherOS actions. With an empty query it shows Favourites, then Recent, then the chosen
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

        // Rows: { kind: "header", label } or a selectable item:
        //   app      { app }                      launch the desktop entry
        //   setting  { title, subtitle, section } open Settings there
        //   action   { title, subtitle, action }  an allowlisted shell action
        //   file     { title, subtitle, path }    open with the default app ("/" prefix)
        //   command  { title, command }           run in your terminal (">" prefix, Enter only)
        //   history  { title }                    a previous search (fills the box)
        readonly property bool fileMode: Config.launcher.searchFiles && query.charAt(0) === "/"
        readonly property bool commandMode: Config.launcher.commandMode && query.charAt(0) === ">"
        readonly property string term: (fileMode || commandMode) ? query.substring(1).trim() : query.trim()
        onTermChanged: if (fileMode) SearchService.search(term)

        readonly property var rows: {
            const out = [];
            if (commandMode) {
                if (term.length > 0) out.push({ kind: "command", title: term, command: term });
                return out;
            }
            if (fileMode) {
                out.push({ kind: "header", label: SearchService.searching ? "Searching files…" : "Files" + (SearchService.backend === "find" ? " (install plocate for instant results)" : "") });
                for (const f of SearchService.results) out.push({ kind: "file", title: f.name, subtitle: f.dir, path: f.path });
                return out;
            }
            if (query.length > 0) {
                for (const a of ApplicationService.search(query)) out.push({ kind: "app", app: a });
                const q = query.toLowerCase();
                const acts = ActionService.actions.filter(function(x) { return x.id !== "none" && x.label.toLowerCase().indexOf(q) >= 0; }).slice(0, 3);
                if (acts.length) {
                    out.push({ kind: "header", label: "Actions" });
                    for (const x of acts) out.push({ kind: "action", title: x.label, subtitle: "AetherOS", action: x.id });
                }
                if (Config.launcher.searchSettings) {
                    const st = SettingsIndex.search(query, 4);
                    if (st.length) {
                        out.push({ kind: "header", label: "Settings" });
                        for (const e of st) out.push({ kind: "setting", title: e.title, subtitle: "Settings", section: e.id });
                    }
                }
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
                const hist = (Config.launcher.history || []).slice(0, 5);
                if (hist.length > 0) {
                    out.push({ kind: "header", label: "Recent searches" });
                    for (const h of hist) out.push({ kind: "history", title: h });
                }
                out.push({ kind: "header", label: "All applications" });
                for (const a of ApplicationService.applications) if (!shown[a.id]) out.push({ kind: "app", app: a });
            } else {
                for (const a of ApplicationService.inCategory(category)) out.push({ kind: "app", app: a });
            }
            return out;
        }

        function _isApp(i) { return i >= 0 && i < rows.length && rows[i].kind !== "header"; }
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

        function _remember() {
            // Only plain searches that led somewhere; never commands or file paths.
            if (fileMode || commandMode || query.trim().length < 2 || Config.launcher.historyLimit === 0) return;
            const h = [query.trim()].concat((Config.launcher.history || []).filter(function(x) { return x !== query.trim(); }));
            Config.launcher.history = h.slice(0, Config.launcher.historyLimit);
        }

        function cycleCategory(dir) {
            const i = categoryList.indexOf(category);
            category = categoryList[(i + dir + categoryList.length) % categoryList.length];
        }

        function launchSelected() {
            if (!_isApp(selectedIndex)) return;
            const r = rows[selectedIndex];
            switch (r.kind) {
            case "history": searchField.text = r.title; return;
            case "app": ApplicationService.launch(r.app); break;
            case "setting": EventBus.settingsRequested(r.section); break;
            case "action": ActionService.run(r.action); break;
            case "file": SearchService.open(r.path); break;
            case "command":
                // Explicit user intent (typed after ">", confirmed with Enter).
                // Runs visibly in the user's terminal, which stays open on the
                // result; the text is a positional argument to a constant script.
                Quickshell.execDetached(Paths.helper("aether-terminal", ["-e", "sh", "-c",
                    'printf "\\033[2m$ %s\\033[0m\\n" "$1"; eval "$1"; printf "\\n[exit %s] Enter closes this window " "$?"; read -r _', "sh", r.command]));
                break;
            }
            _remember();
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

                            AetherIcon {
                                visible: !row.isHeader && row.modelData.kind !== "app"
                                Layout.preferredWidth: 22; Layout.preferredHeight: 22
                                Layout.leftMargin: 5; Layout.rightMargin: 5
                                name: ({ setting: "gear", action: "bolt", file: "image", command: "code", history: "search" })[row.modelData.kind] || "search"
                                color: Colors.textSecondary
                            }
                            AppIcon {
                                visible: !row.isHeader && row.modelData.kind === "app"
                                iconName: row.isHeader || row.modelData.kind !== "app" ? "" : row.modelData.app.icon
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                scale: row.selected && !Motion.reducedMotion ? 1.08 : 1.0
                                Behavior on scale { enabled: !Motion.reducedMotion; NumberAnimation { duration: Motion.fast; easing.type: Motion.easeEmphasized } }
                            }

                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true
                                Text {
                                    text: row.isHeader ? "" : row.modelData.kind === "app" ? row.modelData.app.name
                                        : row.modelData.kind === "command" ? "Run in terminal: " + row.modelData.title : row.modelData.title
                                    color: Colors.textPrimary
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeMd
                                    font.weight: Typography.weightMedium
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: row.isHeader ? "" : row.modelData.kind === "app" ? (row.modelData.app.genericName || row.modelData.app.comment)
                                        : row.modelData.kind === "command" ? "Press Enter to run it in " + (Config.terminal.preferred === "auto" ? "your terminal" : Config.terminal.preferred)
                                        : (row.modelData.subtitle || "")
                                    visible: text.length > 0
                                    color: Colors.textMuted
                                    font.family: Typography.family
                                    font.pixelSize: Typography.sizeXs
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            AetherIcon {
                                readonly property bool fav: !row.isHeader && row.modelData.kind === "app" && ApplicationService.isFavorite(row.modelData.app)
                                visible: !row.isHeader && row.modelData.kind === "app" && (fav || rowArea.containsMouse || row.selected)
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
                                if (mouse.button === Qt.RightButton) { if (row.modelData.kind === "app") ApplicationService.toggleFavorite(row.modelData.app); }
                                else { panel.selectedIndex = row.index; panel.launchSelected(); }
                            }
                        }
                    }
                }

                Text {
                    parent: list
                    anchors.centerIn: parent
                    visible: panel.rows.filter(function(r) { return r.kind !== "header"; }).length === 0
                    text: panel.commandMode ? "Type a command, then Enter to run it in your terminal"
                        : panel.fileMode ? (SearchService.searching ? "" : (panel.term.length < 2 ? "Type at least two letters to search your files" : "No files found"))
                        : ApplicationService.available ? "No results" : "Loading applications…"
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
