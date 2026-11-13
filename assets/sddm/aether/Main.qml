// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Neelampalli Charan Balaji
//
// AetherOS SDDM theme: wallpaper, a large clock and a frosted login card.
// Uses only the standard SDDM greeter API (sddm, userModel, sessionModel,
// config) and QtQuick/QtQuick.Controls from Qt 6.
import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    width: 1920; height: 1080
    color: "#0b0b14"
    readonly property color accent: config.accent || "#b392f0"

    Image {
        anchors.fill: parent
        source: config.background || ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    Rectangle { anchors.fill: parent; color: "#66000010" }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.14
        spacing: 4
        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            color: "white"; font.pixelSize: 112; font.weight: Font.Light
            text: Qt.formatTime(new Date(), "HH:mm")
        }
        Text {
            id: date
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#ddffffff"; font.pixelSize: 24
            text: Qt.formatDate(new Date(), "dddd, d MMMM")
        }
        Timer {
            interval: 1000; running: true; repeat: true
            onTriggered: { clock.text = Qt.formatTime(new Date(), "HH:mm"); date.text = Qt.formatDate(new Date(), "dddd, d MMMM") }
        }
    }

    Rectangle {
        id: card
        width: 380; height: 250; radius: 22
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.52
        color: "#99161622"; border.color: "#33ffffff"; border.width: 1

        Column {
            anchors.centerIn: parent
            width: parent.width - 56
            spacing: 14

            TextField {
                id: user
                width: parent.width
                placeholderText: "User"
                text: userModel.lastUser
                color: "white"
                background: Rectangle { radius: 12; color: "#33ffffff" }
                KeyNavigation.tab: password
            }
            TextField {
                id: password
                width: parent.width
                placeholderText: "Password"
                echoMode: TextInput.Password
                color: "white"
                focus: true
                background: Rectangle { radius: 12; color: "#33ffffff"; border.color: password.activeFocus ? root.accent : "transparent" }
                Keys.onReturnPressed: sddm.login(user.text, password.text, sessionModel.lastIndex)
                Keys.onEnterPressed: sddm.login(user.text, password.text, sessionModel.lastIndex)
            }
            Button {
                width: parent.width
                text: "Log in"
                onClicked: sddm.login(user.text, password.text, sessionModel.lastIndex)
                background: Rectangle { radius: 12; color: root.accent }
            }
            Text {
                id: message
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                color: "#ffb4b4"; font.pixelSize: 14
                text: ""
            }
        }
    }

    Row {
        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 28
        spacing: 12
        Button { text: "Restart"; visible: sddm.canReboot; onClicked: sddm.reboot() }
        Button { text: "Shut down"; visible: sddm.canPowerOff; onClicked: sddm.powerOff() }
    }

    Connections {
        target: sddm
        function onLoginFailed() { message.text = "Wrong password — try again"; password.text = ""; password.forceActiveFocus() }
        function onLoginSucceeded() { message.text = "" }
    }

    Component.onCompleted: password.forceActiveFocus()
}
