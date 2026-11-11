import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"
import "../../../graphics"

// Settings → Style: palette, glass material, corners, icon & cursor themes.
// Palette changes also re-theme kitty/foot/alacritty/ghostty and Hyprland's
// borders (ThemeService → `aether theme apply`).
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg

    property var themes: null
    property string themeMessage: ""
    Component.onCompleted: CliService.run("themes", ["theme", "icons", "--json"], function(ok, d) { if (ok) root.themes = d; })

    SectionLabel { text: "Colour palette" }
    Flow {
        Layout.fillWidth: true
        spacing: Metrics.spaceSm
        Repeater {
            model: Colors.paletteList
            delegate: MotionCard {
                required property var modelData
                required property int index
                width: 132; height: 74
                index: index
                selected: (Config.appearance.palette || "aether") === modelData.id
                fill: modelData.bg
                hoverFill: modelData.surface
                onClicked: Config.appearance.palette = modelData.id
                Column {
                    anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 10
                    spacing: 4
                    Row {
                        spacing: 4
                        Rectangle { width: 16; height: 16; radius: 8; color: modelData.accent }
                        Rectangle { width: 16; height: 16; radius: 8; color: modelData.surface; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.15) }
                    }
                    Text { text: modelData.label; color: modelData.dark ? "#EDEFF7" : "#151824"; font.family: Typography.family; font.pixelSize: Typography.sizeXs; font.weight: Typography.weightSemibold }
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: Config.appearance.palette === "aether" || !Config.appearance.palette
            ? "The AetherOS palette follows the Dark/Light/Auto theme and your accent colour."
            : "Named palettes are either dark or light and keep their own accent, so they stay recognisable."
        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
    }

    // ── Custom theme editor ───────────────────────────────────────────
    SectionLabel { text: "Make your own"; Layout.topMargin: Metrics.spaceSm }
    property string themeName: ""
    property string themeAccent: Colors.accent.toString().toUpperCase()
    property string themeBg: Colors.bg0.toString().toUpperCase()
    property string themeSurface: Colors.surface.toString().toUpperCase()
    property string themeMsg: ""
    function hex(c) { return String(c).toUpperCase(); }
    RowLayout {
        Layout.fillWidth: true
        spacing: Metrics.spaceLg
        // Live preview of the draft.
        Rectangle {
            Layout.preferredWidth: 150; Layout.preferredHeight: 96
            radius: Metrics.radiusLg; color: root.themeBg
            Rectangle { x: 14; y: 14; width: 122; height: 44; radius: 10; color: root.themeSurface
                Rectangle { x: 10; y: 13; width: 18; height: 18; radius: 9; color: root.themeAccent }
                Rectangle { x: 36; y: 15; width: 70; height: 6; radius: 3; color: Colors.textPrimary; opacity: 0.8 }
                Rectangle { x: 36; y: 25; width: 48; height: 5; radius: 2.5; color: Colors.textMuted } }
            Text { x: 14; y: 68; text: root.themeName || "my-theme"; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
        }
        GridLayout {
            columns: 2; columnSpacing: Metrics.spaceSm; rowSpacing: 6
            Repeater {
                model: [{ k: "themeAccent", l: "Accent", sw: ["#7C9CFF", "#B48CFF", "#22E4FF", "#34E5B4", "#FACC15", "#FB923C", "#F87171", "#F472B6"] },
                        { k: "themeBg", l: "Background", sw: ["#000000", "#0A0C12", "#070B17", "#06110F", "#14101A", "#1A1410", "#0F0F10", "#EEF0F6"] },
                        { k: "themeSurface", l: "Surface", sw: ["#111114", "#1E2230", "#17213D", "#13302C", "#241B30", "#2A2118", "#222224", "#FFFFFF"] }]
                delegate: RowLayout {
                    id: rowRow
                    required property var modelData
                    Layout.columnSpan: 2
                    Text { Layout.preferredWidth: 80; text: rowRow.modelData.l; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
                    Repeater {
                        model: rowRow.modelData.sw
                        delegate: ColorSwatch {
                            required property string modelData
                            swatchColor: modelData
                            selected: root[rowRow.modelData.k] === modelData
                            onClicked: root[rowRow.modelData.k] = modelData
                        }
                    }
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Rectangle {
            Layout.preferredWidth: 180; implicitHeight: 30; radius: 15
            color: Colors.withAlpha(Colors.surface, 0.9); border.width: 1; border.color: tn.activeFocus ? Colors.accent : Colors.border
            TextInput { id: tn; anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; verticalAlignment: TextInput.AlignVCenter
                        color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm
                        validator: RegularExpressionValidator { regularExpression: /[a-z0-9][a-z0-9-]{0,39}/ }
                        onTextChanged: root.themeName = text }
            Text { anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; visible: tn.text.length === 0; text: "theme name"; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
        }
        ChipGroup {
            options: [{ value: "save", label: "Save theme (based on " + (Config.appearance.palette || "aether") + ")" }]; current: root.themeName.length >= 2 ? "save" : ""
            onSelected: {
                if (root.themeName.length < 2) { root.themeMsg = "Give it a name first."; return; }
                CliService.run("theme-create", ["themes", "create", root.themeName, "--from", Config.appearance.palette || "aether",
                    "--accent", root.themeAccent, "--bg0", root.themeBg, "--surface", root.themeSurface, "--json"], function(ok, d, e) {
                    root.themeMsg = ok && d.ok ? "Saved. It's in the palette list above." : ((d && d.problems) ? d.problems.join("; ") : e);
                    if (ok && d.ok) { ThemeService.reloadUserPalettes(); Config.appearance.palette = root.themeName; }
                });
            }
        }
        ChipGroup {
            visible: Colors.paletteList.some(function(p) { return p.user && p.id === Config.appearance.palette; })
            options: [{ value: "del", label: "Delete this custom theme" }]; current: ""
            onSelected: { const id = Config.appearance.palette; Config.appearance.palette = "aether";
                CliService.run("theme-delete", ["themes", "delete", id, "--yes", "--json"], function() { ThemeService.reloadUserPalettes(); }); }
        }
    }
    Text { visible: root.themeMsg.length > 0; text: root.themeMsg; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
    Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Share a theme: aether themes export <name> file.json · import: aether themes import file.json <name>"; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs }

    SectionLabel { text: "Glass"; Layout.topMargin: Metrics.spaceSm }
    RowLayout {
        Layout.fillWidth: true
        spacing: Metrics.spaceLg
        // Live preview over a busy backdrop so transparency is visible.
        Item {
            Layout.preferredWidth: 220; Layout.preferredHeight: 120
            Rectangle {
                anchors.fill: parent; radius: Metrics.radiusLg
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Colors.accent }
                    GradientStop { position: 0.5; color: Colors.accentAlt }
                    GradientStop { position: 1; color: Colors.info }
                }
            }
            Repeater {
                model: 6
                delegate: Rectangle { required property int index; x: 12 + index * 34; y: 14 + (index % 2) * 50; width: 26; height: 26; radius: 13; color: Qt.rgba(1, 1, 1, 0.5) }
            }
            GlassPanel {
                anchors.fill: parent; anchors.margins: 18
                radius: Metrics.radiusLg
                tintOpacity: Materials.panelOpacity
                focused: Config.appearance.accentBorders
                Text { anchors.centerIn: parent; text: Materials.current.label; color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; font.weight: Typography.weightSemibold }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Metrics.spaceSm
            ChipGroup {
                Layout.fillWidth: true
                options: Object.keys(Materials.presets).map(function(k) { return { value: k, label: Materials.presets[k].label }; })
                current: Config.appearance.glassStyle
                onSelected: function(v) { Config.appearance.glassStyle = v; }
            }
            SettingRow {
                visible: Config.appearance.glassStyle === "custom"
                label: "Panel opacity"
                Slider { implicitWidth: 180; from: 0.2; to: 1; value: Config.appearance.panelOpacity; onMoved: function(v) { Config.appearance.panelOpacity = Math.round(v * 100) / 100; } }
            }
            Text {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: "Real background blur comes from Hyprland (Settings → Performance → compositor blur). " +
                      (Config.appearance.glassStyle === "adaptive" ? "Adaptive glass turns more opaque on battery." : "")
                color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
            }
        }
    }
    SettingRow {
        label: "Accent edges on focused panels"
        Switch { checked: Config.appearance.accentBorders; onToggled: function(v) { Config.appearance.accentBorders = v; } }
    }
    SettingRow {
        label: "Corner roundness"
        description: Math.round(Config.appearance.cornerScale * 100) + "% of the default radius"
        Slider { implicitWidth: 180; from: 0; to: 1.5; value: Config.appearance.cornerScale; format: function(v) { return Math.round(v * 100) + "%"; }; onMoved: function(v) { Config.appearance.cornerScale = Math.round(v * 20) / 20; } }
    }

    SectionLabel { text: "Icons and cursor"; Layout.topMargin: Metrics.spaceSm }
    Text {
        visible: root.themes === null
        text: "Looking for installed themes…"
        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm
    }
    SettingRow {
        visible: root.themes !== null
        label: "Icon theme"
        description: "Installed themes only (e.g. sudo dnf install papirus-icon-theme). Applies to GTK and Qt apps; restart the shell for its own icons."
        ChipGroup {
            Layout.maximumWidth: 360
            options: root.themes ? root.themes.icons.map(function(t) { return { value: t.id, label: t.name }; }) : []
            current: root.themes && root.themes.current ? (root.themes.current.icons || "") : ""
            onSelected: function(v) {
                CliService.run("set-icons", ["theme", "icons", "--set", v, "--json"], function(ok, d, e) {
                    root.themeMessage = ok ? "Icon theme set (" + d.applied.join(", ") + ")" : ((d && d.error) || e);
                    CliService.run("themes", ["theme", "icons", "--json"], function(ok2, d2) { if (ok2) root.themes = d2; });
                });
            }
        }
    }
    SettingRow {
        visible: root.themes !== null && root.themes.cursors.length > 0
        label: "Cursor theme"
        ChipGroup {
            Layout.maximumWidth: 360
            options: root.themes ? root.themes.cursors.map(function(t) { return { value: t.id, label: t.name }; }) : []
            current: root.themes && root.themes.current ? (root.themes.current.cursor || "") : ""
            onSelected: function(v) {
                CliService.run("set-cursor", ["theme", "cursor", "--set", v, "--size", "24", "--json"], function(ok, d, e) {
                    root.themeMessage = ok ? "Cursor set (" + d.applied.join(", ") + ")" : ((d && d.error) || e);
                    CliService.run("themes", ["theme", "icons", "--json"], function(ok2, d2) { if (ok2) root.themes = d2; });
                });
            }
        }
    }
    Text { visible: root.themeMessage.length > 0; text: root.themeMessage; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
}
