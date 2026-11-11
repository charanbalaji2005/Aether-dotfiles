pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// The assistant's shell side. Talks to `aether ai ask --stream`: the
// conversation is written to the process's stdin (never argv, which other
// users can see in `ps`), replies stream back as JSON lines. Proposed
// actions arrive already validated by the backend's registry; they run only
// when the user clicks Run, through runAction() below — the same allowlisted
// paths the rest of the shell uses. API keys never pass through here.
Singleton {
    id: root

    readonly property bool enabled: Config.ai.enabled
    property var messages: []          // [{role, content, actions?, rejected?, error?}]
    property bool busy: false
    property string partial: ""
    property var status: null

    function refreshStatus(probe) {
        CliService.run("ai-status", ["ai", "status", "--json"].concat(probe ? ["--probe"] : []), function(ok, d, e) { root.status = ok ? d : { error: e }; });
    }

    function send(text) {
        const q = (text || "").trim();
        if (!q || root.busy) return;
        root.messages = root.messages.concat([{ role: "user", content: q.substring(0, 8000) }]);
        root.partial = "";
        root.busy = true;
        proc.running = true;
    }

    function cancel() { if (proc.running) proc.signal(15); }
    function clear() { root.messages = []; root.partial = ""; }

    Process {
        id: proc
        command: Paths.aether(["ai", "ask", "--stream"])
        stdinEnabled: true
        onStarted: {
            const convo = root.messages.filter(function(m) { return !m.error; }).map(function(m) { return { role: m.role, content: m.content }; });
            proc.write(JSON.stringify({ messages: convo }) + "\n");
            proc.stdinEnabled = false;   // closes stdin: the backend reads to EOF
        }
        stdout: SplitParser {
            onRead: function(line) {
                let ev;
                try { ev = JSON.parse(line); } catch (e) { return; }
                if (ev.type === "delta") root.partial += ev.text;
                else if (ev.type === "final") {
                    root.messages = root.messages.concat([{ role: "assistant", content: ev.text, actions: ev.actions || [], rejected: ev.rejected || [] }]);
                    root.partial = "";
                } else if (ev.type === "error") {
                    root.messages = root.messages.concat([{ role: "assistant", content: ev.error, error: true }]);
                    root.partial = "";
                }
            }
        }
        onExited: { root.busy = false; proc.stdinEnabled = true; }
    }

    // Executes a validated action after the user clicked Run.
    function runAction(a, msgIndex) {
        let ok = true;
        const v = a.args || {};
        switch (a.action) {
        case "open-panel": ok = ActionService.run(v.panel === "layouts" ? "none" : v.panel); if (v.panel === "layouts") EventBus.layoutPickerRequested(); break;
        case "open-settings": EventBus.settingsRequested(v.section); break;
        case "launch-app": {
            const app = ApplicationService.applications.find(function(x) { return x.id === v.app; });
            if (app) ApplicationService.launch(app); else ok = false;
            break;
        }
        case "switch-workspace": HyprlandService.switchToWorkspace(v.workspace); break;
        case "apply-layout": LayoutService.apply(v.name, true); break;
        case "apply-profile": ProfileService.apply(v.name); break;
        case "set-quality": Config.effects.quality = v.value; break;
        case "set-theme-mode": Config.appearance.theme = v.value; break;
        case "set-palette": Config.appearance.palette = v.value; break;
        case "set-volume": if (AudioService.available) AudioService.setVolume(v.value / 100); else ok = false; break;
        case "set-dnd": Config.notifications.doNotDisturb = v.value; break;
        case "set-dock": Config.dock.enabled = v.value; break;
        case "set-power-profile": if (PowerProfileService.available && PowerProfileService.has(v.value)) PowerProfileService.set(v.value); else ok = false; break;
        case "lock-screen": EventBus.lockRequested(); break;
        default: ok = false;
        }
        root._markAction(msgIndex, a, ok ? "ran" : "failed");
        auditProc.command = Paths.aether(["ai", "log-action", JSON.stringify({ action: a.action, args: v, ok: ok }), "--ran"]);
        auditProc.running = true;
    }
    function declineAction(a, msgIndex) {
        root._markAction(msgIndex, a, "declined");
        auditProc.command = Paths.aether(["ai", "log-action", JSON.stringify({ action: a.action, args: a.args || {} })]);
        auditProc.running = true;
    }
    function _markAction(i, a, state) {
        const list = root.messages.slice();
        if (!list[i]) return;
        list[i] = Object.assign({}, list[i], { actions: list[i].actions.map(function(x) { return x === a ? Object.assign({}, x, { state: state }) : x; }) });
        root.messages = list;
    }
    Process { id: auditProc }
}
