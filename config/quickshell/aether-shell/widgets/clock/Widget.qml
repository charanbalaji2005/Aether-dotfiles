import QtQuick

// AetherOS built-in widget "Clock" (widget API 1). Data arrives only through
// `api`, which the host fills according to widget.json's permissions.
Item {
    id: root
    property var api: null
    function c(token) { return api && api.theme ? api.theme[token] : "#EDEFF7"; }
    function f() { return api && api.theme ? api.theme.font : "sans-serif"; }

    readonly property var t: api && api.time ? api.time : new Date()
    Column {
        anchors.centerIn: parent
        spacing: 2
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.t, api && api.use24Hour ? "HH:mm" : "h:mm")
            color: root.c("text"); font.family: root.f(); font.pixelSize: 54; font.weight: Font.Light
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.t, "dddd d MMMM")
            color: root.c("textSecondary"); font.family: root.f(); font.pixelSize: 14
        }
    }
}
