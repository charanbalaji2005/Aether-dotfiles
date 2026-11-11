pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../core"

// The desktop's one freedesktop notification daemon (Quickshell's
// NotificationServer). AetherOS deliberately runs no second daemon (mako,
// dunst, swaync) — two servers would fight over org.freedesktop.Notifications.
//
// Also turns shell-originated events (EventBus.notificationRequested:
// "Screenshot saved", "Wallpaper applied", ...) into real toasts, which
// previously went nowhere.
Singleton {
    id: root

    readonly property bool available: true
    property var activeNotifications: []
    readonly property bool doNotDisturb: Config.notifications.doNotDisturb === true

    // Plain JS snapshots taken at arrival time, not live Notification
    // objects — a dismissed notification's object lifetime isn't something
    // to hold onto indefinitely.
    property var history: []
    readonly property int historyLimit: 100
    property int unread: 0
    property int _nextId: 1

    // Toast expiry bookkeeping: [{ n, at }]. One timer serves all toasts.
    property var _expiry: []

    function toggleDnd() {
        Config.notifications.doNotDisturb = !root.doNotDisturb;
    }

    function clearHistory() {
        root.history = [];
        root.unread = 0;
    }

    function markRead() {
        root.unread = 0;
    }

    function removeFromHistory(id) {
        root.history = root.history.filter(function(h) { return h.id !== id; });
    }

    function clearApp(appName) {
        root.history = root.history.filter(function(h) { return h.appName !== appName; });
    }

    // History grouped by application, newest group first.
    function grouped() {
        const groups = [];
        const index = {};
        for (let i = root.history.length - 1; i >= 0; i--) {
            const h = root.history[i];
            const key = h.appName || h.summary;
            if (index[key] === undefined) {
                index[key] = groups.length;
                groups.push({ app: key, appIcon: h.appIcon, items: [] });
            }
            groups[index[key]].items.push(h);
        }
        return groups;
    }

    function _record(snapshot) {
        snapshot.id = root._nextId++;
        root.history = root.history.concat([snapshot]).slice(-root.historyLimit);
        root.unread += 1;
    }

    function _show(n, urgency, timeoutHint) {
        // Keep at most maxVisible toasts; the oldest non-critical goes first.
        let list = root.activeNotifications.concat([n]);
        const maxVisible = Math.max(1, Config.notifications.maxVisible || 4);
        while (list.length > maxVisible) {
            let drop = list.findIndex(function(x) { return x.urgency !== NotificationUrgency.Critical; });
            if (drop < 0) drop = 0;
            const victim = list[drop];
            list.splice(drop, 1);
            root._release(victim);
        }
        root.activeNotifications = list;
        // Quickshell reports expireTimeout in seconds (the D-Bus wire value is
        // ms). Values up to 10 minutes are treated as seconds; anything larger
        // must already be milliseconds.
        const hintMs = timeoutHint > 0 ? (timeoutHint <= 600 ? timeoutHint * 1000 : timeoutHint) : 0;
        const timeout = hintMs > 0 ? hintMs : root._defaultTimeout(urgency);
        if (timeout > 0) root._expiry = root._expiry.concat([{ n: n, at: Date.now() + timeout }]);
    }

    NotificationServer {
        id: server
        imageSupported: true
        actionsSupported: true
        bodyMarkupSupported: true

        onNotification: function(notification) {
            notification.tracked = true;
            const rule = root.ruleFor(notification.appName || "");
            root._record({
                summary: notification.summary || notification.appName || "Notification",
                body: notification.body || "",
                appName: notification.appName || "",
                appIcon: notification.appIcon || "",
                image: notification.image || "",
                urgency: root._urgencyName(notification.urgency),
                time: new Date().toISOString()
            });

            if (rule.mode === "mute") {
                // Kept in history (so nothing is lost), never shown or heard.
                notification.tracked = false;
                return;
            }
            const priority = rule.mode === "priority" || notification.urgency === NotificationUrgency.Critical;
            if (priority) EventBus.islandEvent("notification", { text: (notification.appName ? notification.appName + ": " : "") + (notification.summary || "") });
            if (root.doNotDisturb && !priority) {
                Logger.info("NotificationService", "Suppressed by Do Not Disturb: " + (notification.summary || ""));
                notification.tracked = false;
                return;
            }
            // When the sending app retracts/closes it, drop the toast too
            // (otherwise it would linger as an empty card).
            if (notification.closed && typeof notification.closed.connect === "function") {
                notification.closed.connect(function() {
                    root.activeNotifications = root.activeNotifications.filter(function(n) { return n !== notification; });
                    root._expiry = root._expiry.filter(function(e) { return e.n !== notification; });
                });
            }
            root._show(notification, notification.urgency, notification.expireTimeout);
            if (rule.sound !== false) root.playSound(notification.urgency === NotificationUrgency.Critical ? "critical" : "normal");
        }
    }

    // ── Per-app rules (Settings → Notifications) ──────────────────────
    // mode: "normal" | "priority" (shown and heard even in Do Not Disturb,
    // also surfaced in the island) | "mute" (history only). Matched on the
    // sender's app name, case-insensitively.
    function ruleFor(appName) {
        const a = (appName || "").toLowerCase();
        const r = (Config.notifications.appRules || []).find(function(x) { return x.app.toLowerCase() === a; });
        return r || { mode: "normal", sound: true };
    }
    function setRule(appName, mode, sound) {
        const list = (Config.notifications.appRules || []).filter(function(x) { return x.app.toLowerCase() !== appName.toLowerCase(); });
        if (mode !== "normal" || sound === false) list.push({ app: appName.replace(/[^\w.+-]/g, ""), mode: mode, sound: sound !== false });
        Config.notifications.appRules = list;
    }
    readonly property var knownApps: {
        const seen = {}, out = [];
        for (const h of root.history) if (h.appName && !seen[h.appName]) { seen[h.appName] = true; out.push(h.appName); }
        for (const r of (Config.notifications.appRules || [])) if (!seen[r.app]) { seen[r.app] = true; out.push(r.app); }
        return out.sort();
    }

    // ── Sounds: the freedesktop sound theme via canberra-gtk-play or pw-play ──
    Process { id: soundProcess }
    property real _lastSound: 0
    function playSound(kind) {
        if (!Config.privacy.notificationSounds || (root.doNotDisturb && kind !== "critical")) return;
        const now = Date.now();
        if (now - root._lastSound < 1500 || soundProcess.running) return;   // no machine-gun dings
        root._lastSound = now;
        const id = kind === "critical" ? "dialog-warning" : "message-new-instant";
        soundProcess.command = ["sh", "-c", 'if command -v canberra-gtk-play >/dev/null; then exec canberra-gtk-play -i "$1"; fi; f="/usr/share/sounds/freedesktop/stereo/$1.oga"; [ -f "$f" ] && command -v pw-play >/dev/null && exec pw-play "$f"; exit 0', "sh", id];
        soundProcess.running = true;
    }

    Connections {
        target: EventBus
        function onNotificationRequested(title, body, urgency) {
            const u = urgency === "critical" ? NotificationUrgency.Critical
                : urgency === "low" ? NotificationUrgency.Low : NotificationUrgency.Normal;
            root._record({ summary: title, body: body || "", appName: "AetherOS", appIcon: "", image: "",
                           urgency: urgency || "normal", time: new Date().toISOString() });
            if (root.doNotDisturb && u !== NotificationUrgency.Critical) return;
            // A plain object shaped like a Notification for the toast UI.
            root._show({ summary: title, body: body || "", appName: "AetherOS", appIcon: "", image: "",
                         urgency: u, actions: [], local: true, tracked: true }, u, 0);
        }
    }

    Timer {
        interval: 500
        repeat: true
        running: root._expiry.length > 0
        onTriggered: {
            const now = Date.now();
            const due = root._expiry.filter(function(e) { return e.at <= now; });
            if (due.length === 0) return;
            root._expiry = root._expiry.filter(function(e) { return e.at > now; });
            for (const e of due) root.dismiss(e.n);
        }
    }

    function _urgencyName(u) {
        if (u === NotificationUrgency.Critical) return "critical";
        if (u === NotificationUrgency.Low) return "low";
        return "normal";
    }

    function _defaultTimeout(u) {
        if (u === NotificationUrgency.Critical) return 0; // stays until dismissed
        if (u === NotificationUrgency.Low) return Config.notifications.timeoutLow || 4000;
        return Config.notifications.timeoutNormal || 6000;
    }

    // Hide the toast; the server-side notification stays tracked only while shown.
    function _release(notification) {
        root._expiry = root._expiry.filter(function(e) { return e.n !== notification; });
        if (notification && !notification.local) notification.tracked = false;
    }

    function dismiss(notification) {
        root.activeNotifications = root.activeNotifications.filter(function(n) { return n !== notification; });
        root._release(notification);
    }

    function dismissAll() {
        for (const n of root.activeNotifications) root._release(n);
        root.activeNotifications = [];
    }

    function invokeAction(notification, action) {
        if (action && typeof action.invoke === "function") {
            action.invoke();
        } else {
            Logger.warn("NotificationService", "Action has no invoke() method available");
        }
        if (!notification.resident) {
            dismiss(notification);
        }
    }
}
