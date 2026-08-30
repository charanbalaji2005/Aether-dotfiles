import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import "../../theme"
import "../../core"
import "../../services"

// Uses Quickshell's native Wayland session lock (the real ext-session-lock-v1
// protocol — confirmed against Quickshell's own documented example). Only
// wlroots-based compositors implement it; Hyprland does, GNOME and current
// KWin do not.
//
// CAVEAT — read before trusting this: I could not fetch Quickshell's
// authoritative PamContext example to verify its exact QML member names
// (its docs site blocks automated fetching; I only confirmed PamContext /
// PamResult / PamError exist and their general purpose). The code below is
// my best-effort implementation of the conversation pattern. It's written
// so a wrong member name fails *safe*: `sessionLock.locked = false` only
// ever happens inside the PAM-success branch, so a naming mistake means
// authentication doesn't work (annoying) rather than the screen unlocking
// without a correct password (dangerous) — but test it before relying on
// it as your only way back into a session. Keep a TTY (Ctrl+Alt+F2) or
// another unlocked session available the first time you try this.
Scope {
    id: root

    property bool locked: false
    property string password: ""
    property string statusText: ""
    property bool authenticating: false
    property string clockTime: ""
    property string clockDate: ""

    function _updateClock() {
        root.clockTime = Qt.formatDateTime(new Date(), "hh:mm");
        root.clockDate = Qt.formatDateTime(new Date(), "dddd, d MMMM");
    }

    function requestLock() {
        root.password = "";
        root.statusText = "";
        root.authenticating = false;
        root._updateClock();
        root.locked = true;
    }

    function submit() {
        if (root.authenticating || root.password.length === 0) return;
        root.authenticating = true;
        root.statusText = "Verifying\u2026";
        pam.start();
    }

    Timer {
        interval: 1000
        running: root.locked
        repeat: true
        onTriggered: root._updateClock()
    }

    PamContext {
        id: pam

        onPamMessage: {
            if (this.responseRequired) {
                this.respond(root.password);
            }
        }

        onCompleted: function(result) {
            root.authenticating = false;
            if (result === PamResult.Success) {
                root.statusText = "";
                root.locked = false;
            } else {
                root.statusText = "Incorrect password";
                root.password = "";
            }
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: root.locked

        WlSessionLockSurface {
            color: Colors.bg0

            Item {
                anchors.fill: parent

                Image {
                    anchors.fill: parent
                    source: WallpaperService.currentWallpaper ? ("file://" + WallpaperService.currentWallpaper) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: 0.35
                }

                Rectangle {
                    anchors.fill: parent
                    color: Colors.withAlpha(Colors.bg0, 0.65)
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Metrics.spaceLg
                width: 320

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.clockTime
                    color: Colors.textPrimary
                    font.family: Typography.family
                    font.pixelSize: 56
                    font.weight: Typography.weightSemibold
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.clockDate
                    color: Colors.textSecondary
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeMd
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: Metrics.radiusPill
                    color: Colors.withAlpha(Colors.glass, 0.8)
                    border.width: Metrics.borderWidth
                    border.color: Colors.borderStrong

                    TextInput {
                        id: passwordField
                        anchors.fill: parent
                        anchors.margins: Metrics.spaceMd
                        verticalAlignment: TextInput.AlignVCenter
                        color: Colors.textPrimary
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeMd
                        echoMode: TextInput.Password
                        enabled: !root.authenticating
                        focus: root.locked

                        onTextChanged: root.password = text
                        Keys.onReturnPressed: root.submit()
                        Keys.onEnterPressed: root.submit()
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Metrics.spaceMd
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Password"
                        color: Colors.textMuted
                        font.family: Typography.family
                        font.pixelSize: Typography.sizeMd
                        visible: passwordField.text.length === 0
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.statusText.length > 0
                    text: root.statusText
                    color: root.authenticating ? Colors.textMuted : Colors.danger
                    font.family: Typography.family
                    font.pixelSize: Typography.sizeSm
                }
            }
        }
    }

    Connections {
        target: EventBus
        function onLockRequested() { root.requestLock(); }
    }

    IpcHandler {
        target: "sessionlock"
        function lock(): void { root.requestLock(); }
    }
}
