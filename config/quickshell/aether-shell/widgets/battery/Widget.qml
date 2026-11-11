import QtQuick

// AetherOS built-in widget "Battery" (widget API 1). Data arrives only through
// `api`, which the host fills according to widget.json's permissions.
Item {
    id: root
    property var api: null
    function c(token) { return api && api.theme ? api.theme[token] : "#EDEFF7"; }
    function f() { return api && api.theme ? api.theme.font : "sans-serif"; }

    readonly property var b: api && api.battery ? api.battery : null
    Column {
        anchors.centerIn: parent
        spacing: 4
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.b && root.b.available ? Math.round(root.b.level * 100) + "%" : "—"
            color: root.b && root.b.available && root.b.level < 0.15 && !root.b.charging ? root.c("danger") : root.c("text")
            font.family: root.f(); font.pixelSize: 38; font.weight: Font.Light
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: !root.b || !root.b.available ? "No battery" : root.b.charging ? "Charging" : (root.b.timeText || "On battery")
            color: root.c("textSecondary"); font.family: root.f(); font.pixelSize: 12
        }
    }
}
