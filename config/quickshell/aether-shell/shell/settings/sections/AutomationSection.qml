import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../../../core"
import "../../../services"
import "../../../components"
import "../../../automation/Rules.js" as Rules

// Settings → Automation: WHEN trigger [IF condition] THEN action.
//
// Rules are data from fixed menus — there is no free-text command field
// anywhere, by design. Each rule can be tested (runs its action now),
// enabled or disabled; the log below shows what ran. Import/export:
// `aether automation import|export <file>` (imported rules arrive disabled).
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg

    // ── Draft of the rule being built ─────────────────────────────────
    property string trigger: "power-disconnected"
    property var triggerArgs: ({})
    property string condition: ""
    property var conditionArgs: ({})
    property string action: "set-quality"
    property var actionArgs: ({ value: "eco" })
    property var moreActions: []       // further actions, run in order after the first
    property string error: ""

    readonly property var triggerOptions: Object.keys(Rules.TRIGGERS).map(function(k) { return { value: k, label: Rules.LABELS[k] }; })
    readonly property var conditionOptions: [{ value: "", label: "Always" }].concat(Object.keys(Rules.CONDITIONS).map(function(k) { return { value: k, label: Rules.LABELS[k] }; }))
    readonly property var actionOptions: Object.keys(Rules.ACTIONS).map(function(k) { return { value: k, label: Rules.LABELS[k] }; })

    function draft() {
        const r = { id: AutomationService.newId(), name: "", enabled: true, trigger: Object.assign({ type: root.trigger }, root.triggerArgs),
                    conditions: root.condition ? [Object.assign({ type: root.condition }, root.conditionArgs)] : [],
                    actions: [Object.assign({ type: root.action }, root.actionArgs)].concat(root.moreActions) };
        r.name = Rules.describe(r).substring(0, 120).replace(/[^\w .:@+\-]/g, "");
        return r;
    }

    SettingRow {
        label: "Run automation rules"
        description: AutomationService.breakerReason.length > 0 ? AutomationService.breakerReason
            : PerformanceService.safeMode ? "Paused: safe mode is on" : "Rules react to real events: power, Bluetooth, apps, workspaces, monitors, network, time"
        Switch { checked: Config.automation.enabled; onToggled: function(v) { Config.automation.enabled = v; AutomationService.breakerReason = ""; } }
    }

    // ── Existing rules ────────────────────────────────────────────────
    Repeater {
        model: AutomationService.rules
        delegate: MotionCard {
            id: rc
            required property var modelData
            required property int index
            Layout.fillWidth: true
            implicitHeight: 52
            index: index
            interactive: false
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: Metrics.spaceMd; anchors.rightMargin: Metrics.spaceSm
                spacing: Metrics.spaceSm
                Text { Layout.fillWidth: true; text: Rules.describe(rc.modelData); color: rc.modelData.enabled ? Colors.textPrimary : Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm; elide: Text.ElideRight }
                IconButton { icon: "play"; onClicked: AutomationService.test(rc.modelData) }
                Switch { checked: rc.modelData.enabled; onToggled: function(v) { AutomationService.setEnabled(rc.modelData.id, v); } }
                IconButton { icon: "trash"; onClicked: AutomationService.deleteRule(rc.modelData.id) }
            }
        }
    }
    Text {
        visible: AutomationService.rules.length === 0
        text: "No rules yet — build one below."
        color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeSm
    }
    Text {
        visible: AutomationService.invalidRules.length > 0
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: AutomationService.invalidRules.length + " rule(s) in config.json are invalid and ignored (aether automation validate)."
        color: Colors.warning; font.family: Typography.family; font.pixelSize: Typography.sizeXs
    }

    // ── Builder ───────────────────────────────────────────────────────
    SectionLabel { text: "New rule"; Layout.topMargin: Metrics.spaceSm }
    Step {
        title: "When"
        ChipGroup { Layout.fillWidth: true; options: root.triggerOptions; current: root.trigger; onSelected: function(v) { root.trigger = v; root.triggerArgs = {}; } }
        ParamEditor { spec: Rules.TRIGGERS[root.trigger]; values: root.triggerArgs; onChanged: function(v) { root.triggerArgs = v; } }
    }
    Step {
        title: "If"
        ChipGroup { Layout.fillWidth: true; options: root.conditionOptions; current: root.condition; onSelected: function(v) { root.condition = v; root.conditionArgs = {}; } }
        ParamEditor { spec: root.condition ? Rules.CONDITIONS[root.condition] : ({}); values: root.conditionArgs; onChanged: function(v) { root.conditionArgs = v; } }
    }
    Step {
        title: "Then"
        ChipGroup { Layout.fillWidth: true; options: root.actionOptions; current: root.action; onSelected: function(v) { root.action = v; root.actionArgs = {}; } }
        ParamEditor { spec: Rules.ACTIONS[root.action]; values: root.actionArgs; onChanged: function(v) { root.actionArgs = v; } }
    }
    Repeater {
        model: root.moreActions
        delegate: RowLayout {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: "then " + Rules.LABELS[modelData.type].toLowerCase() + (modelData.value !== undefined ? " → " + modelData.value : "") + (modelData.app ? " → " + modelData.app : "")
                   color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
            IconButton { icon: "trash"; onClicked: root.moreActions = root.moreActions.filter(function(_, i) { return i !== index; }) }
        }
    }
    ChipGroup {
        visible: root.moreActions.length < 4
        options: [{ value: "add", label: "Also do this, then pick another action" }]; current: ""
        onSelected: {
            const a = Object.assign({ type: root.action }, root.actionArgs);
            const err = Rules.checkPart(a, Rules.ACTIONS, "action");
            if (err) { root.error = err; return; }
            root.moreActions = root.moreActions.concat([a]);
            root.error = "";
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: root.error.length ? root.error : Rules.describe(root.draft()); color: root.error.length ? Colors.danger : Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
        ChipGroup { options: [{ value: "test", label: "Test action" }]; current: ""; onSelected: root.error = AutomationService.test(root.draft()) }
        ChipGroup { options: [{ value: "add", label: "Add rule" }]; current: "add"; onSelected: { root.error = AutomationService.saveRule(root.draft()); if (!root.error) root.moreActions = []; } }
    }

    SectionLabel { text: "Recent runs"; Layout.topMargin: Metrics.spaceSm }
    Repeater {
        model: AutomationService.history.slice(0, 8)
        delegate: Text { required property var modelData; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: modelData.time + "  " + (modelData.ok ? "✓ " : "✗ ") + modelData.name + (modelData.detail ? " — " + modelData.detail : ""); color: modelData.ok ? Colors.textSecondary : Colors.danger; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
    }

    component Step: ColumnLayout {
        property string title
        default property alias body: inner.data
        Layout.fillWidth: true
        spacing: Metrics.spaceXs
        Text { text: parent.title; color: Colors.accent; font.family: Typography.family; font.pixelSize: Typography.sizeSm; font.weight: Typography.weightBold }
        ColumnLayout { id: inner; Layout.fillWidth: true; spacing: Metrics.spaceXs }
    }

    // Typed inputs for one part's parameters (percent, workspace, time, …).
    component ParamEditor: ColumnLayout {
        id: pe
        property var spec: ({})
        property var values: ({})
        signal changed(var values)
        Layout.fillWidth: true
        function set(name, v) { const o = Object.assign({}, pe.values); if (v === "" || v === undefined) delete o[name]; else o[name] = v; pe.changed(o); }
        Repeater {
            model: Object.keys(pe.spec || {})
            delegate: RowLayout {
                id: prow
                required property string modelData
                readonly property string kind: pe.spec[modelData].replace("?", "")
                Layout.fillWidth: true
                Text { Layout.preferredWidth: 90; text: prow.modelData; color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs }
                Loader {
                    Layout.fillWidth: true
                    sourceComponent: prow.kind === "bool" ? boolEd : (Rules.ENUMS[prow.kind] ? enumEd : textEd)
                    Component { id: boolEd; Switch { checked: pe.values[prow.modelData] === true; onToggled: function(v) { pe.set(prow.modelData, v); } } }
                    Component { id: enumEd; ChipGroup { options: Rules.ENUMS[prow.kind].map(function(e) { return { value: e, label: e }; }); current: pe.values[prow.modelData] || ""; onSelected: function(v) { pe.set(prow.modelData, v); } } }
                    Component {
                        id: textEd
                        Rectangle {
                            implicitHeight: 30; radius: 15
                            color: Colors.withAlpha(Colors.surface, 0.9); border.width: 1; border.color: ti.activeFocus ? Colors.accent : Colors.border
                            TextInput {
                                id: ti
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                                verticalAlignment: TextInput.AlignVCenter
                                color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm
                                text: pe.values[prow.modelData] !== undefined ? String(pe.values[prow.modelData]) : ""
                                inputMethodHints: prow.kind === "percent" || prow.kind === "workspace" ? Qt.ImhDigitsOnly : Qt.ImhNone
                                onEditingFinished: {
                                    const raw = text.trim();
                                    pe.set(prow.modelData, (prow.kind === "percent" || prow.kind === "workspace") && raw.length ? Number(raw) : raw);
                                }
                            }
                            Text {
                                anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                visible: ti.text.length === 0
                                text: ({ percent: "0-100", workspace: "1-99", time: "HH:MM", app: "app id or window class, e.g. firefox", name: "text", path: "/absolute/path" })[prow.kind] || ""
                                color: Colors.textMuted; font.family: Typography.family; font.pixelSize: Typography.sizeXs
                            }
                        }
                    }
                }
            }
        }
    }
}
