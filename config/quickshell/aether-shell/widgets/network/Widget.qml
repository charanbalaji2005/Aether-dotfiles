import QtQuick

// AetherOS built-in widget "Network" (widget API 1). Data arrives only through
// `api`, which the host fills according to widget.json's permissions.
Item {
    id: root
    property var api: null
    function c(token) { return api && api.theme ? api.theme[token] : "#EDEFF7"; }
    function f() { return api && api.theme ? api.theme.font : "sans-serif"; }

    readonly property var n: api && api.network ? api.network : null
    function rate(b) { return b >= 1048576 ? (b / 1048576).toFixed(1) + " MB/s" : (b / 1024).toFixed(0) + " KB/s"; }
    Column {
        anchors.fill: parent; anchors.margins: 14
        spacing: 6
        Text { width: parent.width; elide: Text.ElideRight; text: root.n && root.n.connected ? root.n.name : "Offline"; color: root.c("text"); font.family: root.f(); font.pixelSize: 14; font.weight: Font.DemiBold }
        Text { text: root.n && root.n.connected ? "↓ " + root.rate(root.n.down) + "    ↑ " + root.rate(root.n.up) : ""; color: root.c("textSecondary"); font.family: root.f(); font.pixelSize: 12 }
    }
}
