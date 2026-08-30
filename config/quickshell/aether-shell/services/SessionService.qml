pragma Singleton
import Quickshell
import Quickshell.Io
import "../core"

// Session/power actions. Lock is delegated via EventBus rather than handled
// directly here, so this service has no Wayland dependency — the actual
// session-lock surface lives in shell/lockscreen/. Keeps the layering rule
// from ARCHITECTURE.md intact: this is a plain system-actions service.
Singleton {
    id: root

    Process { id: suspendProcess; command: ["systemctl", "suspend"] }
    Process { id: rebootProcess; command: ["systemctl", "reboot"] }
    Process { id: shutdownProcess; command: ["systemctl", "poweroff"] }
    Process { id: logoutProcess; command: ["hyprctl", "dispatch", "exit"] }

    function lock() {
        Logger.info("SessionService", "Lock requested");
        EventBus.lockRequested();
    }

    function suspend() {
        Logger.info("SessionService", "Suspend requested");
        suspendProcess.running = true;
    }

    function reboot() {
        Logger.info("SessionService", "Reboot requested");
        rebootProcess.running = true;
    }

    function shutdown() {
        Logger.info("SessionService", "Shutdown requested");
        shutdownProcess.running = true;
    }

    function logout() {
        Logger.info("SessionService", "Logout requested");
        logoutProcess.running = true;
    }
}
