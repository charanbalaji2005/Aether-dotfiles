pragma Singleton
import Quickshell
import Quickshell.Services.Notifications
import "../core"

Singleton {
    id: root

    readonly property bool available: true
    property var activeNotifications: []
    property bool doNotDisturb: false

    // Plain JS snapshots, not live Notification objects — once a
    // notification is dismissed/tracked=false its underlying object's
    // lifetime isn't something this was able to verify as safe to hold a
    // reference to indefinitely, so history stores a copy taken at arrival
    // time instead.
    property var history: []
    readonly property int historyLimit: 100

    function toggleDnd() {
        root.doNotDisturb = !root.doNotDisturb;
    }

    function clearHistory() {
        root.history = [];
    }

    NotificationServer {
        id: server
        imageSupported: true
        actionsSupported: true
        bodyMarkupSupported: true

        onNotification: function(notification) {
            notification.tracked = true;

            const snapshot = {
                summary: notification.summary || notification.appName || "Notification",
                body: notification.body || "",
                appName: notification.appName || "",
                urgency: root._urgencyName(notification.urgency),
                time: new Date().toISOString()
            };
            root.history = root.history.concat([snapshot]).slice(-root.historyLimit);

            if (root.doNotDisturb) {
                Logger.info("NotificationService", "Suppressed by Do Not Disturb: " + snapshot.summary);
                return;
            }

            root.activeNotifications = root.activeNotifications.concat([notification]);

            EventBus.notificationRequested(snapshot.summary, snapshot.body, snapshot.urgency);

            const timeout = notification.expireTimeout > 0
                ? notification.expireTimeout
                : root._defaultTimeout(notification.urgency);
            if (timeout > 0) {
                root._scheduleDismiss(notification, timeout);
            }
        }
    }

    function _urgencyName(u) {
        if (u === NotificationUrgency.Critical) return "critical";
        if (u === NotificationUrgency.Low) return "low";
        return "normal";
    }

    function _defaultTimeout(u) {
        if (u === NotificationUrgency.Critical) return 0; // stays until dismissed
        if (u === NotificationUrgency.Low) return 4000;
        return 6000;
    }

    function _scheduleDismiss(notification, ms) {
        try {
            const timer = Qt.createQmlObject(
                "import QtQuick; Timer { interval: " + ms + "; running: true; repeat: false }",
                root,
                "aetherNotifTimer"
            );
            timer.triggered.connect(function() {
                root.dismiss(notification);
                timer.destroy();
            });
        } catch (e) {
            Logger.error("NotificationService", "Failed to schedule auto-dismiss: " + e);
        }
    }

    function dismiss(notification) {
        root.activeNotifications = root.activeNotifications.filter(function(n) { return n !== notification; });
        notification.tracked = false;
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
