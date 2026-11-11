.pragma library
// Automation rule schema, shared logic for the shell.
//
// These tables mirror lib/aether/automation.py exactly (tests compare
// them). A rule names a trigger, optional conditions and ONE action from
// fixed allowlists — there is no "run a command" action, so a rules file
// imported from anywhere can't execute code.

var TRIGGERS = {
    "power-connected": {},
    "power-disconnected": {},
    "battery-below": { "value": "percent" },
    "bluetooth-connected": { "device": "name?" },
    "bluetooth-disconnected": { "device": "name?" },
    "app-opened": { "app": "app" },
    "app-closed": { "app": "app" },
    "workspace-active": { "value": "workspace" },
    "monitor-connected": {},
    "monitor-disconnected": {},
    "time": { "at": "time" },
    "network-changed": {},
    "focus-started": {},
    "focus-ended": {},
    "startup": {},
    "profile-applied": { "value": "name?" }
};

var CONDITIONS = {
    "on-battery": {},
    "on-ac": {},
    "time-between": { "from": "time", "to": "time" },
    "battery-below": { "value": "percent" },
    "battery-above": { "value": "percent" }
};

var ACTIONS = {
    "set-quality": { "value": "quality" },
    "set-theme-mode": { "value": "thememode" },
    "set-palette": { "value": "name" },
    "set-profile": { "value": "name" },
    "set-power-profile": { "value": "powerprofile" },
    "set-wallpaper": { "value": "path" },
    "next-wallpaper": {},
    "launch-app": { "app": "app" },
    "switch-workspace": { "value": "workspace" },
    "set-volume": { "value": "percent" },
    "set-dnd": { "value": "bool" },
    "set-dock": { "value": "bool" },
    "notify": { "title": "name", "body": "name?" },
    "set-motion": { "value": "motion" },
    "apply-layout": { "value": "name" }
};

var LABELS = {
    "power-connected": "Charger connected", "power-disconnected": "Charger disconnected",
    "battery-below": "Battery drops below", "bluetooth-connected": "Bluetooth device connects",
    "bluetooth-disconnected": "Bluetooth device disconnects", "app-opened": "App opens", "app-closed": "App closes",
    "workspace-active": "Workspace becomes active", "monitor-connected": "Monitor connected",
    "monitor-disconnected": "Monitor disconnected", "time": "At a time of day", "network-changed": "Network changes",
    "focus-started": "Focus session starts", "focus-ended": "Focus session ends",
    "startup": "The desktop starts", "profile-applied": "A desktop profile is applied",
    "set-motion": "Set motion profile", "apply-layout": "Apply window layout",
    "on-battery": "On battery", "on-ac": "On AC power", "time-between": "Between times",
    "battery-above": "Battery above",
    "set-quality": "Set visual quality", "set-theme-mode": "Set theme mode", "set-palette": "Set palette",
    "set-profile": "Apply desktop profile", "set-power-profile": "Set power profile", "set-wallpaper": "Set wallpaper",
    "next-wallpaper": "Next wallpaper", "launch-app": "Launch app", "switch-workspace": "Switch workspace",
    "set-volume": "Set volume", "set-dnd": "Do Not Disturb", "set-dock": "Show dock", "notify": "Show notification"
};

var ENUMS = {
    "quality": ["auto", "eco", "performance", "balanced", "ultra"],
    "motion": ["none", "reduced", "balanced", "smooth", "premium"],
    "thememode": ["dark", "light", "auto"],
    "powerprofile": ["power-saver", "balanced", "performance"]
};

var TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;
var NAME_RE = /^[\w .:@+\-]{1,128}$/;
var APP_RE = /^[\w.+\-]{1,128}$/;

function checkParam(kind, value) {
    var optional = kind.charAt(kind.length - 1) === "?";
    if (optional) kind = kind.substring(0, kind.length - 1);
    if (value === undefined || value === null || value === "") return optional;
    switch (kind) {
    case "percent": return typeof value === "number" && value >= 0 && value <= 100;
    case "workspace": return typeof value === "number" && Math.floor(value) === value && value >= 1 && value <= 99;
    case "bool": return typeof value === "boolean";
    case "time": return typeof value === "string" && TIME_RE.test(value);
    case "name": return typeof value === "string" && NAME_RE.test(value);
    case "app": return typeof value === "string" && APP_RE.test(value);
    case "path": return typeof value === "string" && value.charAt(0) === "/" && value.indexOf("\u0000") < 0
                        && value.split("/").indexOf("..") < 0 && value.length < 1024;
    default: return ENUMS[kind] ? ENUMS[kind].indexOf(value) >= 0 : false;
    }
}

function checkPart(part, table, what) {
    if (!part || typeof part !== "object" || typeof part.type !== "string") return what + " must have a type";
    var spec = table[part.type];
    if (!spec) return "unknown " + what + " '" + part.type + "'";
    for (var name in spec) if (!checkParam(spec[name], part[name])) return what + " " + part.type + ": bad or missing '" + name + "'";
    for (var k in part) if (k !== "type" && !(k in spec)) return what + " " + part.type + ": unexpected field '" + k + "'";
    return "";
}

// Returns "" when the rule is valid, else the problem.
function validate(rule) {
    if (!rule || typeof rule !== "object") return "rule must be an object";
    if (typeof rule.id !== "string" || !/^[A-Za-z0-9_\-]{1,40}$/.test(rule.id)) return "bad rule id";
    var e = checkPart(rule.trigger, TRIGGERS, "trigger");
    if (e) return e;
    if (rule.action !== undefined && rule.actions !== undefined) return "use either action or actions";
    var acts = actionsOf(rule);
    if (!Array.isArray(acts) || acts.length < 1 || acts.length > 5) return "1-5 actions";
    for (var j = 0; j < acts.length; j++) { e = checkPart(acts[j], ACTIONS, "action"); if (e) return e; }
    var conds = rule.conditions || [];
    if (!Array.isArray(conds) || conds.length > 4) return "at most 4 conditions";
    for (var i = 0; i < conds.length; i++) { e = checkPart(conds[i], CONDITIONS, "condition"); if (e) return e; }
    return "";
}

// The 0.3 single-action form and the 1.0 list form, as a list.
function actionsOf(rule) {
    return rule.actions !== undefined ? rule.actions : [rule.action];
}

function minutesOf(hhmm) { var p = hhmm.split(":"); return parseInt(p[0], 10) * 60 + parseInt(p[1], 10); }

// state: { onBattery, battery (0-100), now (Date) }
function conditionsHold(rule, state) {
    var conds = rule.conditions || [];
    for (var i = 0; i < conds.length; i++) {
        var c = conds[i];
        switch (c.type) {
        case "on-battery": if (!state.onBattery) return false; break;
        case "on-ac": if (state.onBattery) return false; break;
        case "battery-below": if (!(state.battery < c.value)) return false; break;
        case "battery-above": if (!(state.battery > c.value)) return false; break;
        case "time-between":
            var m = state.now.getHours() * 60 + state.now.getMinutes();
            var a = minutesOf(c.from), b = minutesOf(c.to);
            var inside = a <= b ? (m >= a && m < b) : (m >= a || m < b);   // wraps past midnight
            if (!inside) return false;
            break;
        }
    }
    return true;
}

// Does an incoming event match this rule's trigger?
function matches(rule, event) {
    var t = rule.trigger;
    if (t.type !== event.type) return false;
    switch (t.type) {
    case "battery-below": return event.value < t.value && event.previous >= t.value;
    case "bluetooth-connected": case "bluetooth-disconnected":
        return !t.device || (event.device || "").toLowerCase() === t.device.toLowerCase();
    case "app-opened": case "app-closed": return (event.app || "").toLowerCase() === t.app.toLowerCase();
    case "workspace-active": return event.value === t.value;
    case "time": return event.at === t.at;
    case "profile-applied": return !t.value || event.value === t.value;
    default: return true;
    }
}

function describe(rule) {
    var t = rule.trigger;
    var tl = LABELS[t.type] + (t.value !== undefined ? " " + t.value + (t.type.indexOf("battery") === 0 ? "%" : "") : "")
             + (t.app ? " " + t.app : "") + (t.at ? " " + t.at : "") + (t.device ? " " + t.device : "");
    var parts = actionsOf(rule).map(function(a) {
        return (LABELS[a.type] + (a.value !== undefined ? " → " + a.value : "") + (a.app ? " → " + a.app : "") + (a.title ? " → " + a.title : "")).toLowerCase();
    });
    return "When " + tl.toLowerCase() + ", " + parts.join(", then ");
}
