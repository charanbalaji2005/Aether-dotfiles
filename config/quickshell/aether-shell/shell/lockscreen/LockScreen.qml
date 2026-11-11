import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import "../../theme"
import "../../core"
import "../../services"
import "../../components"
import "../../animation"
import "../../graphics"

// The AetherOS lock screen.
//
// SECURITY MODEL — read before changing anything here:
//   * Locking uses the Wayland ext-session-lock-v1 protocol through
//     Quickshell's WlSessionLock. While locked, the compositor shows ONLY
//     these surfaces (one per monitor) and routes input only to them; if
//     the shell crashes, Hyprland keeps the session locked (it does not
//     reveal the desktop). Nothing here draws "over" the desktop.
//   * Authentication is PAM, through Quickshell's PamContext (the "login"
//     service in /etc/pam.d). This file never compares passwords itself.
//   * The ONLY statement that unlocks is `root.locked = false` inside the
//     PamResult.Success branch of onCompleted. Every other path (wrong
//     password, PAM error, timeout, a renamed API member) leaves the
//     session locked. Keep it that way.
//   * The typed password lives only in the TextInput and is cleared after
//     every attempt; it is never logged or written anywhere.
//   * Notification *contents* are hidden by default (Settings → Lock
//     screen); only the count is shown.
//   * Crash while locked: Hyprland keeps the session locked (it shows its
//     "lock client died" screen). A marker in $XDG_RUNTIME_DIR records that
//     we were locked; the restarted shell finds it and takes the lock back
//     (needs misc:allow_session_lock_restore, set in hyprland.conf), so the
//     password field returns instead of a dead end. The marker lives in
//     tmpfs, so it never survives a reboot or logout.
//
// Keep a TTY (Ctrl+Alt+F3) available the first time you use it on a new
// system, as with any lock screen.
Scope {
    id: root

    property bool locked: false
    property string statusText: ""
    property bool authenticating: false
    property bool failed: false
    property int failures: 0
    property date now: new Date()

    readonly property string marker: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/aether-shell.locked"
    Process { id: markerWrite }
    Process {
        id: markerCheck
        command: ["test", "-f", root.marker]
        onExited: function(code) {
            if (code === 0) {
                Logger.warn("LockScreen", "Shell restarted while the session was locked: re-acquiring the lock");
                root.requestLock();
            }
        }
    }
    Component.onCompleted: { markerCheck.running = true; hyprlockProbe.running = true; }
    // Never leave a PAM conversation (and its helper process) running.
    Component.onDestruction: if (pam.active) pam.abort()
    onLockedChanged: {
        markerWrite.command = root.locked ? ["touch", root.marker] : ["rm", "-f", root.marker];
        markerWrite.running = true;
    }

    // Lock backend (Settings → Lock screen): "aether" is this file;
    // "hyprlock" hands locking to hyprlock (a dedicated, widely used locker)
    // when it is installed. Every lock path — keybind, idle, before sleep —
    // goes through here, so the choice applies everywhere.
    Process { id: hyprlockProbe; command: ["sh", "-c", "command -v hyprlock >/dev/null"]; onExited: function(code) { root.hyprlockInstalled = code === 0; } }
    property bool hyprlockInstalled: false
    readonly property bool useHyprlock: Config.lock.backend === "hyprlock" && hyprlockInstalled
    Process { id: hyprlockProc; command: ["hyprlock"] }

    function requestLock() {
        if (root.useHyprlock) {
            if (!hyprlockProc.running) hyprlockProc.running = true;
            return;
        }
        root.statusText = "";
        root.failed = false;
        root.authenticating = false;
        root.now = new Date();
        root.locked = true;
    }

    // Called by the focused surface's password field.
    property string _pending: ""
    function submit(password) {
        if (root.authenticating || password.length === 0) return;
        root._pending = password;
        root.authenticating = true;
        root.failed = false;
        root.statusText = "Verifying…";
        pamTimeout.restart();
        // PamContext.start() returns false — without emitting completed() or
        // error() — when the PAM configuration can't be loaded (e.g.
        // /etc/pam.d/login missing). Treat that as a failure: stay locked,
        // re-enable the field, say why.
        if (!pam.start()) {
            Logger.error("LockScreen", "PAM could not start (is /etc/pam.d/" + pam.config + " present?)");
            root._reset("Authentication is unavailable — see aether logs --shell", true);
        }
    }
    function _reset(message, isFailure) {
        pamTimeout.stop();
        root._pending = "";
        root.authenticating = false;
        root.statusText = message;
        if (isFailure) { root.failed = true; root.failures += 1; }
        root.clearFields();
    }
    signal clearFields()

    // A PAM stack that never answers (a hung fingerprint module, say) must
    // not leave the field disabled forever.
    Timer {
        id: pamTimeout
        interval: 30000
        onTriggered: {
            if (typeof pam.abort === "function") pam.abort();
            root._reset("Authentication timed out — try again", true);
        }
    }

    Timer {
        interval: 1000
        running: root.locked
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    PamContext {
        id: pam
        onPamMessage: {
            if (pam.responseRequired) {
                pam.respond(root._pending);
                root._pending = "";
            } else if (pam.message && pam.message.length > 0) {
                // Informational PAM messages (e.g. "Place your finger…").
                root.statusText = pam.message;
            }
        }
        onCompleted: function(result) {
            if (result === PamResult.Success) {
                pamTimeout.stop();
                root._pending = "";
                root.authenticating = false;
                root.statusText = "";
                root.failures = 0;
                root.locked = false;            // ← the only unlock
                root.clearFields();
            } else {
                root._reset(result === PamResult.MaxTries ? "Too many attempts — wait a moment" : "Incorrect password", true);
            }
        }
        onError: function(error) {
            root._reset("Authentication error — try again", true);
        }
    }

    // Video wallpaper and other ambient work pause while locked.
    Binding { target: VideoWallpaperService; property: "locked"; value: root.locked }

    WlSessionLock {
        id: sessionLock
        locked: root.locked

        WlSessionLockSurface {
            id: surface
            color: Colors.bg0

            readonly property bool primary: !ShellState.activeScreen || (screen && screen.name === ShellState.activeScreen.name)

            // ── Background: blurred wallpaper + aurora tint ───────────
            Item {
                anchors.fill: parent
                Image {
                    id: wall
                    anchors.fill: parent
                    source: WallpaperService.currentWallpaper ? ("file://" + WallpaperService.currentWallpaper) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: Math.max(1, surface.width / 2)    // blurred anyway: half size is plenty
                    sourceSize.height: Math.max(1, surface.height / 2)
                    visible: !Config.lock.blurBackground
                }
                MultiEffect {
                    anchors.fill: parent
                    visible: Config.lock.blurBackground && wall.status === Image.Ready
                    source: wall
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 48
                    saturation: -0.15
                    autoPaddingEnabled: false
                }
                AuroraSurface {
                    anchors.fill: parent
                    opacity: wall.status === Image.Ready ? 0.45 : 1
                    running: root.locked && surface.primary
                    strength: 0.35
                }
                Rectangle { anchors.fill: parent; color: Colors.withAlpha(Colors.bg0, 0.35) }
            }

            // ── Clock ─────────────────────────────────────────────────
            Item {
                id: clockArea
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.18
                width: parent.width
                height: clockLoader.item ? clockLoader.item.implicitHeight : 0
                SpringValue { id: entrance; preset: "gentle"; target: root.locked ? 1 : 0 }
                opacity: entrance.value
                transform: Translate { y: (1 - entrance.value) * 24 }

                Loader {
                    id: clockLoader
                    anchors.horizontalCenter: parent.horizontalCenter
                    sourceComponent: ({ digital: digitalClock, large: largeClock, split: splitClock, analog: analogClock })[Config.lock.clockStyle] || digitalClock
                }
            }

            // ── Authentication ────────────────────────────────────────
            ColumnLayout {
                id: auth
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.58
                width: Math.min(340, parent.width - 48)
                spacing: Metrics.spaceMd
                visible: surface.primary   // one password field, on the focused monitor

                // Shake on failure: a decaying horizontal impulse.
                SpringValue { id: shake; preset: "bouncy"; target: 0 }
                Connections {
                    target: root
                    function onFailuresChanged() { if (root.failures > 0 && Motion.animate) shake.impulse(900); }
                    function onClearFields() { passwordField.text = ""; }
                }
                transform: Translate { x: shake.value }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: Metrics.radiusPill
                    color: Colors.withAlpha(Colors.glass, 0.82)
                    border.width: passwordField.activeFocus ? 1.5 : 1
                    border.color: root.failed ? Colors.danger : (passwordField.activeFocus ? Colors.accent : Colors.borderStrong)
                    Behavior on border.color { enabled: Motion.animate; ColorAnimation { duration: Motion.fast } }

                    GlowEdge {
                        anchors.fill: parent
                        radius: parent.radius
                        active: root.authenticating
                        intensity: root.authenticating ? 0.9 : 0
                        visible: intensity > 0
                        period: 1600
                    }

                    TextInput {
                        id: passwordField
                        anchors.fill: parent
                        anchors.leftMargin: Metrics.spaceLg
                        anchors.rightMargin: 44
                        verticalAlignment: TextInput.AlignVCenter
                        color: Colors.textPrimary
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeLg
                        font.letterSpacing: 2
                        echoMode: TextInput.Password
                        passwordCharacter: "●"
                        enabled: !root.authenticating
                        focus: root.locked && surface.primary
                        Keys.onReturnPressed: root.submit(text)
                        Keys.onEnterPressed: root.submit(text)
                        Keys.onEscapePressed: text = ""
                        onTextChanged: if (text.length > 0 && root.failed) root.failed = false
                        Accessible.role: Accessible.EditableText
                        Accessible.name: "Password"
                        Accessible.passwordEdit: true
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Metrics.spaceLg
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Password"
                        color: Colors.textMuted
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeMd
                        visible: passwordField.text.length === 0 && !root.authenticating
                    }
                    Spinner {
                        anchors.right: parent.right; anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18; height: 18
                        visible: root.authenticating
                    }
                    AetherIcon {
                        anchors.right: parent.right; anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18; height: 18
                        visible: !root.authenticating && passwordField.text.length > 0
                        name: "arrow-up"
                        rotation: 90
                        color: Colors.accent
                        MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: root.submit(passwordField.text) }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.statusText.length > 0
                    text: root.statusText
                    color: root.authenticating ? Colors.textSecondary : Colors.danger
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeSm
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.failures >= 3 && !root.authenticating
                    text: "Caps Lock or keyboard layout? (" + root.failures + " failed attempts)"
                    color: Colors.textMuted
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeXs
                }
            }

            // ── Status widgets ────────────────────────────────────────
            RowLayout {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Metrics.spaceXxl
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Metrics.spaceLg
                visible: surface.primary

                // Media
                Rectangle {
                    visible: Config.lock.showMedia && MediaService.available
                    Layout.preferredWidth: 320
                    Layout.preferredHeight: 64
                    radius: Metrics.radiusLg
                    color: Colors.withAlpha(Colors.glass, 0.75)
                    border.width: 1; border.color: Colors.withAlpha(Colors.borderStrong, 0.6)
                    RowLayout {
                        anchors.fill: parent; anchors.margins: Metrics.spaceSm
                        spacing: Metrics.spaceSm
                        Image {
                            Layout.preferredWidth: 46; Layout.preferredHeight: 46
                            source: MediaService.artUrl; fillMode: Image.PreserveAspectCrop
                            asynchronous: true; sourceSize: Qt.size(96, 96)
                            visible: status === Image.Ready
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 0
                            Text { Layout.fillWidth: true; text: MediaService.title || MediaService.identity; color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm; font.weight: Typography.weightMedium; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; text: MediaService.artist; color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeXs; elide: Text.ElideRight }
                        }
                        IconButton { icon: "prev"; onClicked: MediaService.previous() }
                        IconButton { icon: MediaService.playing ? "pause" : "play"; onClicked: MediaService.playPause() }
                        IconButton { icon: "next"; onClicked: MediaService.next() }
                    }
                }

                // Battery
                Rectangle {
                    visible: Config.lock.showBattery && PowerService.available
                    Layout.preferredHeight: 40
                    Layout.preferredWidth: batRow.implicitWidth + Metrics.spaceLg * 2
                    radius: 20
                    color: Colors.withAlpha(Colors.glass, 0.75)
                    RowLayout {
                        id: batRow
                        anchors.centerIn: parent
                        spacing: Metrics.spaceSm
                        BatteryIcon { style: Config.battery.style === "percent" ? "classic" : Config.battery.style; level: PowerService.percentage / 100; charging: PowerService.charging; state: PowerService.level }
                        Text { text: Math.round(PowerService.percentage) + "%"; color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm }
                    }
                }

                // Notifications: count only unless the user allowed contents.
                Rectangle {
                    readonly property int count: NotificationService.unread
                    visible: count > 0
                    Layout.preferredHeight: 40
                    Layout.preferredWidth: nRow.implicitWidth + Metrics.spaceLg * 2
                    radius: 20
                    color: Colors.withAlpha(Colors.glass, 0.75)
                    RowLayout {
                        id: nRow
                        anchors.centerIn: parent
                        spacing: Metrics.spaceSm
                        AetherIcon { width: 14; height: 14; name: "bell"; color: Colors.textSecondary }
                        Text {
                            text: Config.lock.hideNotificationContent || NotificationService.history.length === 0
                                ? parent.parent.count + " new notification" + (parent.parent.count === 1 ? "" : "s")
                                : (NotificationService.history[0].appName || "") + ": " + (NotificationService.history[0].summary || "")
                            color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeSm
                            elide: Text.ElideRight
                            Layout.maximumWidth: 320
                        }
                    }
                }
            }
        }
    }

    // ── Clock styles ───────────────────────────────────────────────────
    Component {
        id: digitalClock
        Column {
            spacing: Metrics.spaceXs
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(root.now, Config.general.use24Hour ? "HH:mm" : "h:mm")
                color: Colors.textPrimary
                font.family: Typography.familyDisplay; font.pixelSize: Typography.s(88); font.weight: Typography.weightLight
                font.features: { "tnum": 1 }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: Config.lock.showDate
                text: Qt.formatDateTime(root.now, "dddd, d MMMM")
                color: Colors.textSecondary
                font.family: Typography.family; font.pixelSize: Typography.sizeLg
            }
        }
    }
    Component {
        id: largeClock
        Column {
            spacing: 0
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(root.now, Config.general.use24Hour ? "HH" : "h")
                color: Colors.textPrimary
                font.family: Typography.familyDisplay; font.pixelSize: Typography.s(150); font.weight: Typography.weightBold
                lineHeight: 0.85
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(root.now, "mm")
                color: Colors.accent
                font.family: Typography.familyDisplay; font.pixelSize: Typography.s(150); font.weight: Typography.weightLight
                lineHeight: 0.85
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: Config.lock.showDate
                text: Qt.formatDateTime(root.now, "dddd d MMMM").toUpperCase()
                color: Colors.textSecondary
                font.family: Typography.family; font.pixelSize: Typography.sizeSm; font.letterSpacing: 3
            }
        }
    }
    Component {
        id: splitClock
        Row {
            spacing: Metrics.spaceXl
            Text {
                text: Qt.formatDateTime(root.now, Config.general.use24Hour ? "HH:mm" : "h:mm")
                color: Colors.textPrimary
                font.family: Typography.familyDisplay; font.pixelSize: Typography.s(72); font.weight: Typography.weightSemibold
                font.features: { "tnum": 1 }
            }
            Rectangle { width: 2; height: 80; color: Colors.accent; anchors.verticalCenter: parent.verticalCenter }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                visible: Config.lock.showDate
                Text { text: Qt.formatDateTime(root.now, "dddd"); color: Colors.textPrimary; font.family: Typography.family; font.pixelSize: Typography.sizeXl; font.weight: Typography.weightMedium }
                Text { text: Qt.formatDateTime(root.now, "d MMMM yyyy"); color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeMd }
            }
        }
    }
    Component {
        id: analogClock
        Column {
            spacing: Metrics.spaceMd
            Item {
                id: face
                anchors.horizontalCenter: parent.horizontalCenter
                width: Typography.s(180); height: width
                readonly property real h: root.now.getHours() % 12 + root.now.getMinutes() / 60
                readonly property real m: root.now.getMinutes() + root.now.getSeconds() / 60
                Rectangle { anchors.fill: parent; radius: width / 2; color: Colors.withAlpha(Colors.glass, 0.55); border.width: 1.5; border.color: Colors.withAlpha(Colors.borderStrong, 0.7) }
                Repeater {
                    model: 12
                    delegate: Rectangle {
                        required property int index
                        width: index % 3 === 0 ? 3 : 1.5; height: index % 3 === 0 ? 12 : 7
                        color: Colors.textSecondary
                        x: face.width / 2 - width / 2; y: 6
                        transform: Rotation { origin.x: width / 2; origin.y: face.height / 2 - 6; angle: index * 30 }
                    }
                }
                Hand { length: face.width * 0.26; thickness: 4; angle: face.h * 30; tone: Colors.textPrimary }
                Hand { length: face.width * 0.38; thickness: 2.5; angle: face.m * 6; tone: Colors.textPrimary }
                Hand { length: face.width * 0.42; thickness: 1.2; angle: root.now.getSeconds() * 6; tone: Colors.accent }
                Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: Colors.accent }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: Config.lock.showDate
                text: Qt.formatDateTime(root.now, "dddd, d MMMM")
                color: Colors.textSecondary; font.family: Typography.family; font.pixelSize: Typography.sizeLg
            }
        }
    }
    component Hand: Rectangle {
        property real length
        property real thickness
        property real angle
        property color tone
        width: thickness; height: length; radius: thickness / 2
        color: tone
        x: parent.width / 2 - width / 2
        y: parent.height / 2 - length
        transformOrigin: Item.Bottom      // pivot at the face centre
        rotation: angle
    }

    Connections {
        target: EventBus
        function onLockRequested() { root.requestLock(); }
    }

    IpcHandler {
        target: "sessionlock"
        function lock(): void { root.requestLock(); }
        function isLocked(): bool { return root.locked; }
    }
}
