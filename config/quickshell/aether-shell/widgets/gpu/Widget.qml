import QtQuick

// AetherOS built-in widget "GPU" (widget API 1). Data arrives only through
// `api`, which the host fills according to widget.json's permissions.
Item {
    id: root
    property var api: null
    function c(token) { return api && api.theme ? api.theme[token] : "#EDEFF7"; }
    function f() { return api && api.theme ? api.theme.font : "sans-serif"; }

    readonly property var g: api && api.gpu ? api.gpu : null
    Column {
        anchors.fill: parent; anchors.margins: 14
        spacing: 6
        Text { width: parent.width; elide: Text.ElideRight; text: root.g && root.g.name ? root.g.name : "GPU"; color: root.c("text"); font.family: root.f(); font.pixelSize: 13; font.weight: Font.DemiBold }
        Text {
            text: !root.g || !root.g.available ? (root.g && root.g.note ? root.g.note : "No telemetry")
                : (root.g.usage >= 0 ? Math.round(root.g.usage * 100) + "% busy" : "—") + (root.g.tempC > 0 ? "  ·  " + Math.round(root.g.tempC) + " °C" : "")
            width: parent.width; wrapMode: Text.WordWrap
            color: root.c("textSecondary"); font.family: root.f(); font.pixelSize: 12
        }
        Text {
            visible: root.g && root.g.vramTotal > 0
            text: root.g ? (root.g.vramUsed / 1073741824).toFixed(1) + " / " + (root.g.vramTotal / 1073741824).toFixed(1) + " GiB VRAM" : ""
            color: root.c("textSecondary"); font.family: root.f(); font.pixelSize: 12
        }
        Rectangle {
            visible: root.g && root.g.vramTotal > 0
            width: parent.width; height: 4; radius: 2; color: root.c("border")
            Rectangle { width: root.g && root.g.vramTotal > 0 ? parent.width * root.g.vramUsed / root.g.vramTotal : 0; height: 4; radius: 2; color: root.c("accent") }
        }
    }
}
